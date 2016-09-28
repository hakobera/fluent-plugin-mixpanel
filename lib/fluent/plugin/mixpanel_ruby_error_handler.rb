require 'mixpanel-ruby'

class Fluent::MixpanelOutputErrorHandler < Mixpanel::ErrorHandler
   def initialize(logger)
     @logger = logger
   end

   def handle(error)
     # Default behavior is to not return an error. Mixpanel-ruby gem returns
     # true/false. If there is an error, an optional error handler is called.
     # In this case, here, we only want to log the error for future development
     # of error handling.
     @logger.error "MixpanelOutputErrorHandler:\n\tClass: #{error.class.to_s}\n\tMessage: #{error.message}\n\tBacktrace: #{error.backtrace}"
   end
end
