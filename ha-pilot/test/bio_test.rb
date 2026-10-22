require 'minitest/autorun'
require 'jekyll'
require_relative '../plugins/bio'

Bio = Jekyll::HomeAssistant::Bio

# Just enough of a Jekyll post for the resolver.
FakePost = Struct.new(:url, :date, :data)

class BioTest < Minitest::Test
  NOW = Time.utc(2026, 10, 22)
  SITE = 'https://www.home-assistant.io'.freeze

  POSTS = [
    FakePost.new('/blog/2026/10/01/release-202610/', Time.utc(2026, 10, 1),
                 { 'title' => '2026.10', 'categories' => %w[Release-Notes Core],
                   'og_image' => '/images/blog/2026-10/social.jpg' }),
    FakePost.new('/blog/2026/10/14/voice/', Time.utc(2026, 10, 14),
                 { 'title' => 'Voice', 'categories' => ['Voice'],
                   'og_image' => '/images/voice.jpg' }),
  ].freeze

  def config(overrides = {})
    {
      'sections' => [{ 'type' => 'feed', 'source' => 'latest', 'limit' => 1 }],
      'sources' => {
        'blog' => { 'type' => 'posts' },
        'latest' => { 'type' => 'pinned', 'items' => [], 'fallback' => 'blog' },
      },
    }.merge(overrides)
  end

  def labels(cfg)
    Bio.resolve(cfg, POSTS, NOW, SITE).flat_map { |s| s['tiles'].map { |t| t['label'] } }
  end

  def assert_invalid(cfg, message)
    error = assert_raises(Bio::ConfigError) { Bio.validate!(cfg) }
    assert_includes error.message, message
  end

  # -- Validation: an editing mistake must name the line ----------------------

  def test_valid_config_passes
    assert Bio.validate!(config)
  end

  def test_unknown_source_names_the_declared_ones
    cfg = config('sections' => [{ 'type' => 'feed', 'source' => 'lastest' }])
    assert_invalid cfg, 'sections[0].source: unknown source "lastest". Declared: blog, latest'
  end

  def test_unknown_section_type
    assert_invalid config('sections' => [{ 'type' => 'link' }]), 'sections[0].type: must be one of: links, feed'
  end

  def test_bad_date
    cfg = config('sections' => [{ 'type' => 'links',
                                  'items' => [{ 'label' => 'x', 'url' => '/x/', 'ends' => '31/11/2026' }] }])
    assert_invalid cfg, 'sections[0].items[0].ends: "31/11/2026" is not a date'
  end

  def test_relative_url_without_slash
    cfg = config('sections' => [{ 'type' => 'links', 'items' => [{ 'label' => 'x', 'url' => 'docs' }] }])
    assert_invalid cfg, 'sections[0].items[0].url: must be a site path'
  end

  def test_fallback_loop
    cfg = config('sources' => {
      'a' => { 'type' => 'pinned', 'fallback' => 'b' },
      'b' => { 'type' => 'pinned', 'fallback' => 'a' },
      'latest' => { 'type' => 'posts' },
    })
    assert_invalid cfg, 'fallback loop: a → b → a'
  end

  def test_limit_out_of_range
    cfg = config('sections' => [{ 'type' => 'feed', 'source' => 'blog', 'limit' => 0 }])
    assert_invalid cfg, 'sections[0].limit: must be a whole number from 1 to 10'
  end

  # -- Pins --------------------------------------------------------------------

  def test_empty_pin_falls_back_to_newest_post
    assert_equal ['Voice'], labels(config)
  end

  def test_active_pin_wins
    cfg = config
    cfg['sources']['latest']['items'] = [{ 'title' => 'Launch', 'url' => '/launch/', 'expires' => Date.new(2026, 11, 1) }]
    assert_equal ['Launch'], labels(cfg)
  end

  def test_expired_pin_hands_back_to_the_feed
    cfg = config
    cfg['sources']['latest']['items'] = [{ 'title' => 'Launch', 'url' => '/launch/', 'expires' => Date.new(2026, 10, 1) }]
    assert_equal ['Voice'], labels(cfg)
  end

  # -- Sources and scheduling --------------------------------------------------

  def test_category_filter
    cfg = config('sections' => [{ 'type' => 'feed', 'source' => 'releases' }],
                 'sources' => { 'releases' => { 'type' => 'posts', 'category' => 'Release-Notes' } })
    assert_equal ['2026.10'], labels(cfg)
  end

  def test_scheduling_window
    cfg = config('sections' => [{ 'type' => 'links', 'items' => [
      { 'label' => 'Running', 'url' => '/a/', 'starts' => Date.new(2026, 10, 1), 'ends' => Date.new(2026, 11, 1) },
      { 'label' => 'Not yet', 'url' => '/b/', 'starts' => Date.new(2026, 11, 1) },
      { 'label' => 'Over', 'url' => '/c/', 'ends' => Date.new(2026, 10, 1) },
    ] }])
    assert_equal ['Running'], labels(cfg)
  end

  def test_empty_section_is_omitted
    cfg = config('sections' => [{ 'type' => 'links', 'title' => 'Gone',
                                  'items' => [{ 'label' => 'Over', 'url' => '/c/', 'ends' => Date.new(2026, 1, 1) }] }])
    assert_empty Bio.resolve(cfg, POSTS, NOW, SITE)
  end

  # -- Images ------------------------------------------------------------------

  def test_auto_image_on_internal_post_uses_its_og_image
    item = { 'url' => '/blog/2026/10/14/voice/', 'image' => 'auto' }
    assert_equal '/images/voice.jpg', Bio.image_for(item, POSTS, SITE)
  end

  def test_auto_image_on_external_url_uses_ohf_endpoint
    item = { 'url' => 'https://www.openhomefoundation.org/survey/', 'image' => 'auto' }
    assert_equal 'https://assets.openhomefoundation.org/opengraph?url=https%3A%2F%2Fwww.openhomefoundation.org%2Fsurvey%2F',
                 Bio.image_for(item, POSTS, SITE)
  end

  def test_feed_images_only_when_section_asks
    cfg = config('sections' => [{ 'type' => 'feed', 'source' => 'blog' }])
    assert_nil Bio.resolve(cfg, POSTS, NOW, SITE).first['tiles'].first['image']
    cfg['sections'].first['images'] = true
    assert_equal '/images/voice.jpg', Bio.resolve(cfg, POSTS, NOW, SITE).first['tiles'].first['image']
  end
end
