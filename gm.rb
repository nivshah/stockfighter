require 'rubygems'
require 'httparty'
require 'json'

module StockFighter
    class GameManager
        attr_accessor :api_key, :level_name, :instance_id, :account, :venue, :ticker
        BaseUrl = "https://www.stockfighter.io/gm"
        def initialize(api_key, level_name)
            self.api_key = api_key
            self.level_name = level_name

            self.start
        end

        def level_url
            "#{BaseUrl}/levels/#{self.level_name}"
        end

        def instance_url
            "#{BaseUrl}/instances/#{self.instance_id}"
        end

        def start
            response = HTTParty.post(self.level_url,
                          :cookies => {"api_key" => self.api_key}
                         )
            self.instance_id = response.parsed_response['instanceId']
            self.account = response.parsed_response['account']
            self.venue = response.parsed_response['venues'][0]
            self.ticker = response.parsed_response['tickers'][0]
        end

        def restart
        end

        def stop
            HTTParty.post("#{self.instance_url}/stop",
                          :cookies => {"api_key" => self.api_key}
                         )
        end

        def resume
        end

        def state
            response = HTTParty.get(self.level_url,
                                    :cookies => {"api_key" => self.api_key}
                                   )

            return response.body
        end
    end
end
