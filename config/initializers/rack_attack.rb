# config/initializers/rack_attack.rb
class Rack::Attack
  # Throttle all requests by IP
  throttle('req/ip', limit: 300, period: 5.minutes) do |req|
    req.ip
  end
  
  # Throttle conversion requests by IP (more strict)
  throttle('conversions/ip', limit: 10, period: 15.minutes) do |req|
    req.ip if req.path == '/conversions' && req.post?
  end
  
  # Ban IPs that try to abuse the system
  blocklist('ban excessive conversion attempts') do |req|
    Rack::Attack::Allow2Ban.filter(req.ip, maxretry: 20, findtime: 5.minutes, bantime: 1.hour) do
      req.path == '/conversions' && req.post?
    end
  end
end