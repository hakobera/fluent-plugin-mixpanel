require 'helper'

class MixpanelRubyErrorHandlerTest < Test::Unit::TestCase

  def test_handle
    mixpanel_error = Fluent::MixpanelOutput::MixpanelError.new("Foobar failed")
    @io = StringIO.new
    logger = Logger.new(@io)
    error = Fluent::MixpanelOutputErrorHandler.new(logger)
    error.handle(mixpanel_error)

    output = @io.string
    expected_output = "MixpanelOutputErrorHandler:\n\tClass: Fluent::MixpanelOutput::MixpanelError\n\tMessage: Foobar failed\n\tBacktrace: \n"
    assert_match expected_output, output
  end
end
