# Runs the Rakefile's newsletter_data task against a Ghost-shaped RSS feed,
# with the network stubbed. Point HA_SITE at a home-assistant.io checkout.
require 'minitest/autorun'
require 'net/http'
require 'rake'
require 'tmpdir'
require 'json'

GHOST_RSS = <<~XML.freeze
  <?xml version="1.0" encoding="UTF-8"?>
  <rss xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:content="http://purl.org/rss/1.0/modules/content/"
       xmlns:atom="http://www.w3.org/2005/Atom" xmlns:media="http://search.yahoo.com/mrss/" version="2.0">
    <channel>
      <title><![CDATA[Open Home Foundation]]></title>
      <item>
        <title><![CDATA[The open home, October edition]]></title>
        <link>https://newsletter.openhomefoundation.org/october/</link>
        <pubDate>Wed, 01 Oct 2026 09:00:00 GMT</pubDate>
        <media:content url="https://newsletter.openhomefoundation.org/content/images/2026/10/october.png" medium="image"/>
      </item>
      <item>
        <title><![CDATA[September edition]]></title>
        <link>https://newsletter.openhomefoundation.org/september/</link>
        <pubDate>Mon, 01 Sep 2026 09:00:00 GMT</pubDate>
      </item>
    </channel>
  </rss>
XML

class NewsletterTaskTest < Minitest::Test
  SITE = ENV.fetch('HA_SITE', '/home/user/home-assistant.io')

  def run_task(body = nil, error: nil, existing: nil)
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p("#{dir}/source/_data")
      File.write("#{dir}/source/_data/newsletter_data.json", existing) if existing
      Dir.chdir(dir) do
        Rake.application = Rake::Application.new
        Rake.application.instance_eval { @rakefile = 'Rakefile' }
        Rake.load_rakefile("#{SITE}/Rakefile")
        Net::HTTP.stub(:get, ->(_uri) { raise error if error; body }) do
          capture_io { Rake::Task[:newsletter_data].invoke }
        end
      end
      return JSON.parse(File.read("#{dir}/source/_data/newsletter_data.json"))
    end
  end

  def test_keeps_link_and_date_for_the_bio_page
    editions = run_task(GHOST_RSS)
    # The second item has no cover image, which the community page needs.
    assert_equal 1, editions.length
    assert_equal({ 'title' => 'The open home, October edition',
                   'image' => 'https://newsletter.openhomefoundation.org/content/images/size/w960/2026/10/october.png',
                   'url' => 'https://newsletter.openhomefoundation.org/october/',
                   'date' => '2026-10-01T09:00:00Z' },
                 editions.first)
  end

  def test_network_failure_keeps_the_existing_file
    assert_equal [{ 'title' => 'kept' }], run_task(error: SocketError.new('offline'), existing: '[{"title":"kept"}]')
  end

  # The built-in fallback has covers for the community page but no links, so
  # the bio page leaves the newsletter out rather than linking nowhere.
  def test_offline_fallback_is_skipped_by_the_bio_page
    require_relative '../plugins/bio'
    editions = run_task(error: SocketError.new('offline'))
    refute_empty editions
    assert_empty Jekyll::HomeAssistant::Bio.data_items(editions, 'newsletter')
  end

  def test_garbage_response_does_not_fail_the_build
    refute_empty run_task('<html>Gateway timeout</html>')
  end
end
