require 'rubygems'
require 'mechanize'
require 'nokogiri'

class RubyFitbit

  attr_reader :calories, :steps, :miles_walked, :sedentary_active, :lightly_active, :fairly_active, :very_active

  def initialize(email, pass)
    @email = email
    @pass = pass
    @agent = WWW::Mechanize.new #{|a| a.log = Logger.new(STDERR) } #turn on if debugging
    @logged_in = false 
    get_data
  end

  #todo only login once
  def login
    unless @logged_in
      page = @agent.get 'https://www.fitbit.com/login'
      
      form = page.forms.first
      form.email = @email
      form.password = @pass
      
      page = @agent.submit(form, form.buttons.first)
      
      @userId = page.search("//div[@class='accountLinks']").search("a")[0]['href'].gsub('/user/','')
      # @agent.cookie_jar.jar["www.fitbit.com"]['/']['uid'].value
      # @agent.cookie_jar.jar["www.fitbit.com"]['/']['sid'].value

      @logged_in = true
    end
  end

  def get_data(date = Time.now)
    login

    date = get_fitbit_date_format(date).gsub('-','/')
    page = @agent.get "https://www.fitbit.com/#{date}"

    @calories = page.search("//div[@class='data']").search("span").children[0].text
    @steps = page.search("//div[@class='data']").search("span").children[2].text.strip
    @miles_walked = page.search("//div[@class='data']").search("span").children[3].text.strip
    @sedentary_active = page.search("//div[@class='sedentary caption']/div[@class='number']").text.strip
    @lightly_active = page.search("//div[@class='lightly caption']/div[@class='number']").text.strip
    @fairly_active = page.search("//div[@class='caption fairly']/div[@class='number']").text.strip
    @very_active = page.search("//div[@class='caption very']/div[@class='number']").text.strip
  end

  def get_steps_data(date = Time.now)
    get_graph_data('intradaySteps',date)
  end

  def get_calorie_data(date = Time.now)
    get_graph_data('intradayCaloriesBurned',date)
  end
  
  def get_activity_score_data(date = Time.now)
    get_graph_data('intradayActiveScore',date)
  end
  
  def get_graph_data(graph_type = 'intradaySteps', date = Time.now, data_version = '2108')
    login

    date = get_fitbit_date_format(date)

    params = {:userId => @userId,
      :type => graph_type,
      :version => "amchart",
      :dataVersion => data_version,
      :chart_Type => "column2d",
      :period => "1d",
      :dateTo => date}

    params = WWW::Mechanize::Util.build_query_string(params)
    uri = "http://www.fitbit.com/graph/getGraphData?#{params}"

    page = @agent.get uri
    doc = Nokogiri::HTML(page.content)
    minutes_segment = 0
    chart_data = {}
    doc.xpath('//data/chart/graphs/graph/value').each do |ele|
      moment = Time.parse(date)+(5*60*minutes_segment)
      minutes_segment += 1
      chart_data[moment] = ele.child.text
    end 

    chart_data
  end

  def get_fitbit_date_format(date)
    #fitbit date format expects like so: 2010-06-24
    date = date.strftime("%Y-%m-%d")
  end

end
