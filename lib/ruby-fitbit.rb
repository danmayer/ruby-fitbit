require 'rubygems'
require 'mechanize'
require 'nokogiri'
require 'json'

class RubyFitbit

  #TODO change tests so reader isn't needed
  attr_reader :logged_in

  def initialize(email, pass)
    @email = email
    @pass = pass
    @agent = Mechanize.new #{|a| a.log = Logger.new(STDERR) } #turn on if debugging
    @logged_in = false 
    @cached_data = {}
  end

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

  def submit_food_log(options = {})
    login

    date = options.fetch(:date) {Time.now}
    date = get_fitbit_date_format(date)
    meal_type = options.fetch(:meal_type){'7'}
    food_id = options[:food_id]
    food = options[:food]
    raise "food_id or food required to submit food log" unless food_id || food
    unless food_id
      food_recommendation = get_food_items(food)
      if food_recommendation.length > 0
        food_recommendation = food_recommendation.first
        food = food_recommendation['name']
        food_id = food_recommendation['id']
      end
    end

    unit_id = options[:unit_id]
    unit = options[:unit]
    raise "unit_id or unit required to submit food log" unless unit_id || unit
    unless unit_id
      unit_id = get_unit_id_for_unit(unit)
    end

    page = @agent.get 'http://www.fitbit.com/foods/log'

    form = page.forms[1]

    form.action="/foods/log/foodLog?apiFormat=htmljson&log=on&date=#{date}"
    form.foodId = food_id
    form.foodselectinput = food
    form.unitId = unit_id
    form.quantityselectinput = unit
    form.quantityConsumed = unit
    form.mealTypeId = meal_type
    result = @agent.submit(form, form.buttons.first)
  end
  
  def submit_weight_log(options = {})
    login
    
    weight_units = {:lbs => "US", :stone => "UK", :kg => "METRIC"}
    
    date = options.fetch(:date) {Time.now}
    date = get_fitbit_date_format(date)
    
    unit = options[:unit]
    unit_id = weight_units[unit.to_sym]
    raise "#{unit} isn't one of Fitbit's units. Try #{weight_units.keys.join(", ")} instead." unless unit_id
    
    page = @agent.get 'http://www.fitbit.com/weight'
    
    form = page.forms[1]
    form.action="/measure/measurements?apiFormat=json&log=on&date=#{date}"
    form.send(options[:unit].to_sym, options[:weight])
    form.weightState = unit_id
    form.bodyFat = options[:percentage_fat]
    
    result = @agent.submit(form, form.buttons.first)
  end
  
  def get_unit_id_for_unit(unit)
    unit_id   = nil
    unit_type = unit.match(/\d+ (.*)/)[1]

    type_map = {'oz' => '226',
                'lb' => '180',
                'gram' => '147',
                'kilogram' => '389',
                'roll' => '290',
                'serving' => '304',
                'link' => '188',
                'piece' => '251',
                'fl oz' => '128',
                'ml' => '209',
                'tsp' => '364',
                'tbsp' => '349',
                'cup' => '91',
                'pint' => '256',
                'slice' => '311',
                'liter' => '189',
                'quart' => '279',
                'entree' => '117',
                'portion' => '270'
    }

    unit_id   = type_map[unit_type]
    unit_id
  end

  def get_food_items(food="Coffe")
    login
    result = @agent.get "http://www.fitbit.com/solr/food/select?q=#{food}&wt=foodjson&qt=food"
    foods = JSON.parse(result.body).first[1]["foods"]
    foods
  end

  def get_eaten_calories(date = Time.now)
    login

    date = get_fitbit_date_format(date).gsub('-','/')
    page = @agent.get "https://www.fitbit.com/foods/log/#{date}"
    calories_data = page.search("//div[@id='dailyTotals']").first
    calories_xml = calories_data.to_xml
    calories_text = calories_data.text
    {:calories_xml => calories_xml, :calories_text => calories_text}
  end

  def get_data(date = Time.now)
    login

    date = get_fitbit_date_format(date).gsub('-','/')
    return @cached_data[date] if @cached_data[date]

    page = @agent.get "https://www.fitbit.com/#{date}"
    
    data = {}
    data['calories'] = 0
    data['steps'] = 0
    data['miles_walked'] = 0.0

    page.search("//div[@class='data']").each do |datadiv|
      if datadiv.text.match(/calories burned$/)
        data['calories'] = datadiv.search("span").first.text.to_i
      elsif datadiv.text.match(/calories eaten/)
        data['calories_eaten'] = datadiv.search("span").first.text.to_i
      elsif datadiv.text.match(/steps taken/)
        data['steps'] = datadiv.search("span").first.text.to_i
      elsif datadiv.text.match(/miles traveled/)
        data['miles_walked'] = datadiv.search("span").first.text.to_f
      end
    end

    data['sedentary_active'] = page.search("//div[@class='sedentary caption']/div[@class='number']").text.strip
    data['lightly_active'] = page.search("//div[@class='lightly caption']/div[@class='number']").text.strip
    data['fairly_active'] = page.search("//div[@class='caption fairly']/div[@class='number']").text.strip
    data['very_active'] = page.search("//div[@class='caption very']/div[@class='number']").text.strip
    data['sedentary_active_in_minutes'] = get_minutes_from_time(data['sedentary_active'])
    data['lightly_active_in_minutes'] = get_minutes_from_time(data['lightly_active'])
    data['fairly_active_in_minutes'] = get_minutes_from_time(data['fairly_active'])
    data['very_active_in_minutes'] = get_minutes_from_time(data['very_active'])

    @cached_data[date] = data
    data
  end

  def get_aggregated_data(start_date = Time.now, end_date = Time.now) 
    data = {}
    formatted_date = get_fitbit_date_format(end_date)
    data[formatted_date] = get_data(end_date)
    
    date = end_date + (24 * 60 * 60)
    while date < start_date
      formatted_date = get_fitbit_date_format(date)
      data[formatted_date] = get_data(date)
      date = date + (24 * 60 * 60)
    end

    data
  end

  def get_avg_data(start_date = Time.now, end_date = Time.now) 
    data = {}
    data['calories'] = 0
    data['steps'] = 0
    data['miles_walked'] = 0
    data['sedentary_active_in_minutes'] = 0
    data['lightly_active_in_minutes'] = 0
    data['fairly_active_in_minutes'] = 0
    data['very_active_in_minutes'] = 0
    days = 0
    
    days_data = get_aggregated_data(start_date, end_date) 
    days_data.keys.each do |key|
      days += 1
      current_data = days_data[key]
      data.keys.each do |stat|
        data[stat] += current_data[stat].to_f
      end
    end

    data.keys.each do |key|
      data[key] = (data[key]/days)
    end

    data
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

    params = Mechanize::Util.build_query_string(params)
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

  def get_minutes_from_time(str)
    if m = str.to_s.strip.match(/^((\d+)hrs?)? ?((\d+)min)?$/)
      hrs = m[1].to_i * 60
      mins = m[3].to_i
      return (hrs + mins)
    end

    return 0
  end

end
