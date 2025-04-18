# config/sitemap.rb
SitemapGenerator::Sitemap.default_host = "https://www.ytconverter.net"
SitemapGenerator::Sitemap.compress = false

SitemapGenerator::Sitemap.create do
  # Add root path
  add '/', :changefreq => 'daily', :priority => 1.0

  # Add new YouTube to MP3 path
  add '/youtube-to-mp3', :changefreq => 'daily', :priority => 0.9
  
  # Add static pages
  add '/contact', :changefreq => 'monthly', :priority => 0.7
  add '/copyright-claims', :changefreq => 'monthly', :priority => 0.7
  add '/privacy-policy', :changefreq => 'monthly', :priority => 0.7
  add '/terms-of-use', :changefreq => 'monthly', :priority => 0.7
end