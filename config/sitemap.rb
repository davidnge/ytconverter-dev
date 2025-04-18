# config/sitemap.rb
SitemapGenerator::Sitemap.default_host = "https://www.ytconverter.net"

SitemapGenerator::Sitemap.create do
  # Add root path
  add '/', :changefreq => 'daily', :priority => 1.0
  
  # Add static pages
  add '/contact', :changefreq => 'monthly'
  add '/copyright-claims', :changefreq => 'monthly'
  add '/privacy-policy', :changefreq => 'monthly'
  add '/terms-of-use', :changefreq => 'monthly'
end