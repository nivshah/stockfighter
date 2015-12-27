require 'rubygems'
require 'httparty'
require 'json'
require "redis"
require 'thread'
require 'faye/websocket'
require 'eventmachine'

Thread.abort_on_exception=true

class MarketMaker
    attr_accessor :account, :venue, :stock
    BaseUrl = "https://api.stockfighter.io/ob/api"
    BaseWebSocket = "wss://api.stockfighter.io/ob/api/ws"
    ApiKey = "5e54239545b1adc32cea423e94a1ccc083110abe"

    def initialize(account, venue, stock)
        self.account = account
        self.venue = venue
        self.stock = stock
    end

    def quote_url
        "#{BaseUrl}/venues/#{self.venue}/stocks/#{self.stock}/quote"
    end

    def quote_web_socket
        "#{BaseWebSocket}/#{self.account}/venues/#{self.venue}/tickertape/stocks/#{self.stock}"
    end

    def transaction_url
        "#{BaseUrl}/venues/#{self.venue}/stocks/#{self.stock}/orders"
    end

    def apiKey
        ApiKey
    end
end

class Ask
    # posts a new ask to the server
    attr_accessor :order_id
    def initialize(market, quote)
        order = {
            "account" => market.account,
            "venue" => market.venue,
            "symbol" => market.stock,
            "price" => self.calculate_price(quote),
            "qty" => self.calculate_quantity(quote),
            "direction" => "sell",
            "orderType" => "limit"
        }

        sell = HTTParty.post(market.transaction_url,
                            :body => JSON.dump(order),
                            :headers => {"X-Starfighter-Authorization" => market.apiKey}
                            )

        self.order_id = sell.parsed_response['id'].to_i
    end

    def calculate_price(quote)
        if quote['last']
            return quote['last'].to_i + 1
        elsif quote['bid']
            return quote['bid'].to_i + 1
        end
    end

    def calculate_quantity(quote)
        if Position.get_shares < -500
            return 25
        elsif Position.get_shares < -250
            return 75
        else
            return 100
        end
    end
end

class AskWorker
    # wipes out old ask
    # makes new ask
    # figures out what price / quantity should be
    attr_accessor :last_order_id, :market

    def initialize(market)
        self.market = market
    end

    def last_order_url
        "#{self.market.transaction_url}/#{self.last_order_id}"
    end

    def update(quote)
        if self.last_order_id
            # update position with the last_order status

            delete = HTTParty.delete(self.last_order_url,
                            :headers => {"X-Starfighter-Authorization" => self.market.apiKey}
                           )

            quantity = delete.parsed_response['totalFilled'].to_i
            #puts delete.body
            Position.sell_shares(quantity)
        end

        ask = Ask.new(self.market, quote)
        self.last_order_id = ask.order_id
    end
end

class Bid
    # posts a new bid to the server
    attr_accessor :order_id
    def initialize(market, quote)
        order = {
            "account" => market.account,
            "venue" => market.venue,
            "symbol" => market.stock,
            "price" => self.calculate_price(quote),
            "qty" => self.calculate_quantity(quote),
            "direction" => "buy",
            "orderType" => "limit"
        }

        buy = HTTParty.post(market.transaction_url,
                            :body => JSON.dump(order),
                            :headers => {"X-Starfighter-Authorization" => market.apiKey}
                            )

        self.order_id = buy.parsed_response['id'].to_i
    end

    def calculate_price(quote)
        if quote['last']
            return quote['last'].to_i - 1
        elsif quote['ask']
            return quote['ask'].to_i - 1
        end
    end

    def calculate_quantity(quote)
        if Position.get_shares > 500
            return 25
        elsif Position.get_shares > 250
            return 75
        else
            return 100
        end
    end
end

class BidWorker
    # wipes out old bid
    # makes new bid
    # figures out what price / quantity should be
    attr_accessor :last_order_id, :market

    def initialize(market)
        self.market = market
    end

    def last_order_url
        "#{self.market.transaction_url}/#{self.last_order_id}"
    end

    def update(quote)
        if self.last_order_id
            # nuke this order
            delete = HTTParty.delete(self.last_order_url,
                            :headers => {"X-Starfighter-Authorization" => self.market.apiKey}
                            )

            quantity = delete.parsed_response['totalFilled'].to_i
            #puts delete.body
            Position.buy_shares(quantity)
        end

        bid = Bid.new(self.market, quote)
        self.last_order_id = bid.order_id
    end
end

class Quote
    # Thread for checking quotes
    #   write latest bid and asks to redis
    attr_accessor :latest
end

class Position
    # queries redis, updates position
    # Thread for checking current position
    #   Read redis state
    #   do math
    RedisKey = "sell_side_shares_held"

    def self.reset_shares
        redis = Redis.new
        return redis.set(RedisKey, 0)
    end

    def self.get_shares
        redis = Redis.new
        return redis.get(RedisKey).to_i
    end

    def self.sell_shares(quantity)
        redis = Redis.new

        begin
            redis.watch(RedisKey)
            redis.multi
            new_count = redis.get(RedisKey).to_i - quantity
            # puts "SELLING #{self.get_shares} #{quantity} #{new_count}"
            redis.set(RedisKey, new_count)
            redis.exec
        rescue Exception
            retry
        end
    end

    def self.buy_shares(quantity)
        redis = Redis.new

        begin
            redis.watch(RedisKey)
            redis.multi
            new_count = redis.get(RedisKey).to_i + quantity
            # puts "BUYING #{self.get_shares} #{quantity} #{new_count}"
            redis.set(RedisKey, new_count)
            redis.exec
        rescue Exception
            retry
        end
    end
end

# changes every time you reset the level
account = "WAB15078684"
venue = "UNICBEX"
stock = "GHOI"

market = MarketMaker.new(account, venue, stock)
quote = Quote.new
bid_worker = BidWorker.new(market)
ask_worker = AskWorker.new(market)
Position.reset_shares

Thread.new {
    EM.run {
        ws = Faye::WebSocket::Client.new(market.quote_web_socket)

        ws.on :message do |event|
            quote.latest = JSON.parse(event.data)['quote']
        end
    }
}

while true
    if quote.latest
        Thread.new { ask_worker.update(quote.latest) }
        Thread.new { bid_worker.update(quote.latest) }
    end
    puts "Current position: #{Position.get_shares}"
    sleep 0.5
end