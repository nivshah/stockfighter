require 'rubygems'
require 'httparty'
require 'json'

api_key = "5e54239545b1adc32cea423e94a1ccc083110abe"
venue = "XBWEX"
stock = "WPI"
base_url = "https://api.stockfighter.io/ob/api"

account = "YAW50939894"
shares_to_get = 100000

while shares_to_get > 0
  quote = HTTParty.get("#{base_url}/venues/#{venue}/stocks/#{stock}/quote")

  if quote.parsed_response['ask'].to_i == 0 || quote.parsed_response['bid'].to_i == 0
    sleep 5
    next
  end

  order = {
    "account" => account,
    "venue" => venue,
    "symbol" => stock,
    "price" => ((quote.parsed_response['ask'].to_i + quote.parsed_response['last'].to_i) / 2).to_i,
    "qty" => (((quote.parsed_response['askSize'].to_i * 2) + quote.parsed_response['bidSize'].to_i) / 3).to_i,
    "direction" => "buy",
    "orderType" => "limit"
  }

  buy = HTTParty.post("#{base_url}/venues/#{venue}/stocks/#{stock}/orders",
                      :body => JSON.dump(order),
                      :headers => {"X-Starfighter-Authorization" => api_key}
                     )
  puts buy.body
  buy_order_id = buy.parsed_response['id']
  sleep 20
end
