require 'rubygems'
require 'mechanize'

class RubyFitbit

  attr_reader :calories, :steps, :miles_walked, :sedentary_active, :lightly_active, :fairly_active, :very_active

  def initialize(email, pass)
    @email = email
    @pass = pass
    get_data
  end

  def get_data
    agent = WWW::Mechanize.new #{|a| a.log = Logger.new(STDERR) } #turn on if debugging
    page = agent.get 'https://www.fitbit.com/login'
    
    form = page.forms.first
    form.email = @email
    form.password = @pass

    page = agent.submit(form, form.buttons.first)

    @calories = page.search("//div[@class='data']").search("span").children[0].text
    @steps = page.search("//div[@class='data']").search("span").children[2].text.strip
    @miles_walked = page.search("//div[@class='data']").search("span").children[3].text.strip
    @sedentary_active = page.search("//div[@class='sedentary caption']/div[@class='number']").text.strip
    @lightly_active = page.search("//div[@class='lightly caption']/div[@class='number']").text.strip
    @fairly_active = page.search("//div[@class='caption fairly']/div[@class='number']").text.strip
    @very_active = page.search("//div[@class='caption very']/div[@class='number']").text.strip
  end

end
