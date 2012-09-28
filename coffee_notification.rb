#Require rubygems for old (pre 1.9 versions of Ruby and Debian-based systems)
require 'rubygems'
require 'client_world_connection.rb'
require 'wm_data.rb'
require 'buffer_manip.rb'
#For password echo
require 'highline/import'

#For emailing
require 'pony'

if (ARGV.length != 4)
  puts "This program requires the following arguments:"
  puts "\t<world model ip> <world model port> <gmail address> <destination email>"
  puts "The gmail address is used to send the notification email to the destination address."
  exit
end
wmip         = ARGV[0]
port         = ARGV[1]
@email       = ARGV[2]
@destination = ARGV[3]
@pword = ask("Enter password for email address #{@email}:  ") { |q| q.echo = false }

def getOwlTime()
  t = Time.now
  return t.tv_sec * 1000 + t.usec/10**3
end

#Make sure at least 20 minutes pass between notifications
TWENTY_MINUTES = 20 * 1000 * 60

#Remember when the last brew event occured for each coffee pot
@prev_happened = {}
#Wait for the the idle status to transition from idle to non-idle and back.
@latch_triggered = {}

#Connect to the world model as a client
@cwm = ClientWorldConnection.new(wmip, port)

Signal.trap("SIGTERM") {
  puts "Exiting..."
  @cwm.close() if (@cwm.connected)
  exit
}

Signal.trap("SIGINT") {
  puts "Exiting..."
  @cwm.close() if (@cwm.connected)
  exit
}

#Subscribe to idle information from anything with coffee pot in its name
#Get updates every 1000 milliseconds
coffee_request = @cwm.streamRequest(".*(coffee pot).*", ['idle'], 1000)
while (@cwm.connected and not coffee_request.isComplete())
  result = coffee_request.next()
  result.each_pair {|uri, attributes|
    #Initialize historic map if this is the first time seeing this coffee pot.
    if (not @prev_happened.has_key? uri)
      puts "Found new coffee pot named \"#{uri}\""
      @prev_happened[uri] = 0
      @latch_triggered[uri] = [false, getOwlTime()]
    end
    #There should only be one idle or brewing attribute -- behavior will be strange with more than one
    if (not attributes.empty?)
      #Unpack single-byte boolean value
      idle_status = attributes[0].data.unpack('C')[0]
      #Trigger the latch if the lid is open/brewing is starting
      if (0 == idle_status)
        @latch_triggered[uri] = [true, getOwlTime()]
      elsif (@latch_triggered[uri][0] == true and (@latch_triggered[uri][1] + 2500) < getOwlTime())
        #Brewing/latch ended and were previously brewing for at least 2.5 seconds
        @latch_triggered[uri] = [false, 0]
        if (@prev_happened[uri] + TWENTY_MINUTES < getOwlTime())
          @prev_happened[uri] = getOwlTime()
          puts "#{uri} is brewing coffee at time #{@prev_happened[uri]}"
          #Send out a notification email
          begin
            Pony.mail(:to        => @destination,
                      :subject   => "fresh coffee at #{uri}",
                      :body      => "Someone is brewing fresh coffee at #{uri}!",
                      :via => :smtp,
                      :via_options => {
              :address   => 'smtp.gmail.com',
              :port      => '587',
              :enable_starttls_auto => true,
              :domain    => 'grail.winlab',
              :user_name => @email,
              :password  => @pword})
          rescue
            puts "Problem sending email!"
          end
        end
      end
    end
  }
end

puts "Lost connection to world model!"

