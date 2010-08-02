require File.expand_path('./helper', File.dirname(__FILE__))
require 'webmock/test_unit'
require 'vcr'
require 'ruby-fitbit'
require 'mocha'

class TestRubyFitbit < Test::Unit::TestCase
  include WebMock

VCR.config do |c|
  c.cassette_library_dir = 'fixtures/vcr_cassettes'
  c.http_stubbing_library = :webmock
end

#TODO this is a mess it took awhile to figure out a way to make the tests work at all clean this up

  HEADERS = <<END
HTTP/1.1 200 OK
Server: Apache-Coyote/1.1
Expires: Thu, 01 Jan 1970 00:00:00 GMT
Cache-control: no-store, no-cache, must-revalidate
Pragma: no-cache
Content-Type: text/html;charset=UTF-8
Content-Language: en-US
Transfer-Encoding: chunked
Date: Mon, 19 Jul 2010 00:49:32 GMT
END

  def fake_login
    # Created a response via
    #`curl -is https://www.fitbit.com/login > ./test/responses/loginpage.txt`
    raw_response_file = File.new("./test/responses/loginpage.txt")
    stub_request(:get, "https://www.fitbit.com/login").to_return(raw_response_file)
  end

  should "initialize" do
    fake_login

     response = <<END
#{HEADERS}
    <div class="accountLinks"> 
   
        <ul> 
            <li>Hi <a href="/user/22FAKE" style="border: 0; padding: 0;">dan@fake.com</a></li> 
</ul></div>
END

    stub_request(:post, "https://www.fitbit.com/login").to_return(response)
    RubyFitbit.any_instance.stubs(:get_data)
    fitbit = RubyFitbit.new("not@fake.com","pass")
    fitbit.login
    assert fitbit.logged_in

    def fitbit.userId
      @userId
    end
    assert_equal "22FAKE", fitbit.userId
  end

  should "get data" do
    fake_login
    data = File.read("./test/responses/data.txt")
    response = "#{HEADERS} #{data}"

    date = Time.now()
    date = date.strftime("%Y/%m/%d")
    stub_request(:get, "https://www.fitbit.com/#{date}").to_return(response)

    RubyFitbit.any_instance.stubs(:login)
    fitbit = RubyFitbit.new("fake@fake.com","pass")
    def fitbit.set_logged_in(val) 
      @logged_in = val
    end
    fitbit.set_logged_in(true)
    
    assert_equal "1928", fitbit.calories, "wrong calories"
    assert_equal "7821", fitbit.steps, "wrong steps"
    assert_equal "3.38", fitbit.miles_walked, "wrong miles"
    assert_equal "16hrs 58min", fitbit.sedentary_active, "wrong sedentary"
    assert_equal "1hr 42min", fitbit.lightly_active, "wrong lightly"
    assert_equal "1hr 51min", fitbit.fairly_active, "wrong fairly"
    assert_equal "17min", fitbit.very_active, "wrong very"
  end

  should "use VCR successfully" do
    fitbit = nil
    VCR.use_cassette('fitbit_get_data', :record => :new_episodes) do
      fitbit = RubyFitbit.new("fake@fake.com","fake")
    end
   
    assert_equal "0",fitbit.steps
  end

end
