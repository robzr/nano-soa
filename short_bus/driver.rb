require 'pp'
require 'set'

module ShortBus
  class Driver
    include DebugMessage

    attr_reader :services
    attr_accessor :debug

    DEFAULT_DRIVER_OPTIONS = {
      debug: false,
      default_message_spec: '**',
      default_publisher_spec: nil,
      default_thread_count: 1
    }

    def initialize(*options)
      @options = DEFAULT_DRIVER_OPTIONS
      @options.merge! options[0] if options[0].is_a?(Hash)
      @debug = @options[:debug]

      @messages = Queue.new
      @services = {}
      @threads = { message_router: launch_message_router }
    end

    def subscribe(*args, &block)
      service_args = {
        debug: @debug,
        driver: self,
        message_spec: @options[:default_message_spec],
        name: nil,
        publisher_spec: @options[:default_publisher_spec],
        service: block_given? ? block.to_proc : nil, 
        thread_count: @options[:default_thread_count],
      }.merge args[0].is_a?(Hash) ? args[0] : { service: args[0] }

      debug_message("#subscribe service: #{service_args[:service]}")
      service_ref = Service.new(service_args)
      @services[service_ref.name] = service_ref
    end

    def publish(arg)
      if message = convert_to_message(arg)
        @messages.push message
        message
      end
    end

    alias_method :<<, :publish

    def unsubscribe(service)
      if service.is_a? ShortBus::Service
        unsubscribe(service.name)
      elsif @services.has_key? service
        @services[service].stop
        @services.delete service
      end      
    end
    
    private

    def convert_to_message(arg)
      if arg.is_a? ShortBus::Message
        arg
      elsif arg.is_a? String
        Message.new(arg)
      elsif arg.is_a?(Array) && arg[0].is_a?(String)
        Message.new(arg)
      elsif arg.is_a?(Hash) && arg.has_key?(:event)
        publisher = arg.has_key?(:publisher) ? arg[:publisher] : nil
        payload = arg.has_key?(:payload) ? arg[:payload] : nil
        Message.new(event: arg[:event], payload: payload, publisher: publisher)
      end
    end

    def launch_message_router
      Thread.new do
        loop do 
          message = @messages.shift
          debug_message "route_message(#{message})"
          @services.values.each { |service| service.check message }
        end
      end
    end
  end
end

