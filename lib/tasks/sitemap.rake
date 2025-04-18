# lib/tasks/sitemap.rake
namespace :sitemap do
  desc "Generate sitemap"
  task generate: :environment do
    # First, remove any existing sitemap files
    FileUtils.rm_f(Dir.glob("#{Rails.root}/public/sitemap*.{xml,xml.gz}"))
    
    # Set up sitemap generator
    host = Rails.env.production? ? "https://www.ytconverter.net" : "http://localhost:3000"
    SitemapGenerator::Sitemap.default_host = host
    SitemapGenerator::Sitemap.compress = false
    SitemapGenerator::Sitemap.namer = SitemapGenerator::SimpleNamer.new(:sitemap, :extension => '.xml')
    
    puts "Generating uncompressed sitemap with host: #{host}"
    SitemapGenerator::Sitemap.verbose = true
    SitemapGenerator::Sitemap.create
  end
end