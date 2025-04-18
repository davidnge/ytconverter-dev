# lib/tasks/sitemap.rake
namespace :sitemap do
  desc "Generate sitemap"
  task generate: :environment do
    puts "Setting up sitemap generator..."
    # Set default host - for local development, you can use localhost
    host = Rails.env.production? ? "https://www.ytconverter.net" : "http://localhost:3000"
    SitemapGenerator::Sitemap.default_host = host
    
    puts "Generating sitemap with host: #{host}"
    SitemapGenerator::Sitemap.verbose = true
    SitemapGenerator::Sitemap.create
  end
end