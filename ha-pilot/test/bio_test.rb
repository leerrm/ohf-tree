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

  # On release day the release post is also the newest post. It belongs under
  # "Latest release"; the blog section moves on to its next post.
  def release_day(order)
    posts = [POSTS[0].dup.tap { |p| p.date = Time.utc(2026, 10, 20) }, POSTS[1]]
    sections = {
      'blog' => { 'type' => 'feed', 'title' => 'Blog', 'source' => 'blog', 'limit' => 1 },
      'releases' => { 'type' => 'feed', 'title' => 'Release', 'source' => 'releases', 'limit' => 1 },
    }
    cfg = config(
      'sections' => order.map { |key| sections[key] },
      'sources' => { 'blog' => { 'type' => 'posts' },
                     'releases' => { 'type' => 'posts', 'category' => 'Release-Notes' } },
    )
    Bio.resolve(cfg, posts, NOW, SITE).to_h { |s| [s['title'], s['tiles'].map { |t| t['label'] }] }
  end

  def test_release_post_stays_under_releases_when_blog_is_first
    assert_equal({ 'Blog' => ['Voice'], 'Release' => ['2026.10'] }, release_day(%w[blog releases]))
  end

  def test_release_post_stays_under_releases_when_releases_is_first
    assert_equal({ 'Release' => ['2026.10'], 'Blog' => ['Voice'] }, release_day(%w[releases blog]))
  end

  def test_pin_outranks_a_category_feed
    cfg = config(
      'sections' => [
        { 'type' => 'feed', 'title' => 'Release', 'source' => 'releases' },
        { 'type' => 'feed', 'title' => 'Pinned', 'source' => 'latest' },
      ],
      'sources' => {
        'releases' => { 'type' => 'posts', 'category' => 'Release-Notes' },
        'latest' => { 'type' => 'pinned',
                      'items' => [{ 'title' => 'Pinned release', 'url' => '/blog/2026/10/01/release-202610/' }] },
      },
    )
    tiles = Bio.resolve(cfg, POSTS, NOW, SITE).to_h { |s| [s['title'], s['tiles'].map { |t| t['label'] }] }
    assert_equal({ 'Pinned' => ['Pinned release'] }, tiles)
  end

  # -- Downloaded data (the newsletter) ---------------------------------------

  NEWSLETTER = [
    { 'title' => 'Older issue', 'url' => 'https://newsletter.example/older/',
      'date' => '2026-09-01T09:00:00Z', 'image' => 'https://newsletter.example/older.png' },
    { 'title' => 'Latest issue', 'url' => 'https://newsletter.example/latest/',
      'date' => '2026-10-01T09:00:00Z', 'image' => 'https://newsletter.example/latest.png' },
    { 'title' => '', 'url' => 'https://newsletter.example/broken/' },
  ].freeze

  def newsletter_config
    config('sections' => [{ 'type' => 'feed', 'source' => 'newsletter', 'limit' => 1, 'images' => true }],
           'sources' => { 'newsletter' => { 'type' => 'data', 'file' => 'newsletter' } })
  end

  def test_data_source_shows_the_newest_issue_with_its_image
    tile = Bio.resolve(newsletter_config, POSTS, NOW, SITE, { 'newsletter' => NEWSLETTER }).first['tiles'].first
    assert_equal 'Latest issue', tile['label']
    assert_equal 'https://newsletter.example/latest.png', tile['image']
    assert_equal 'October 1, 2026', tile['note']
  end

  def test_data_source_missing_or_empty_omits_the_section
    assert_empty Bio.resolve(newsletter_config, POSTS, NOW, SITE, {})
    assert_empty Bio.resolve(newsletter_config, POSTS, NOW, SITE, { 'newsletter' => [] })
    assert_empty Bio.resolve(newsletter_config, POSTS, NOW, SITE, { 'newsletter' => 'not a list' })
  end

  def test_data_source_needs_a_file_name
    cfg = config('sources' => { 'latest' => { 'type' => 'data', 'file' => '../secrets' } })
    assert_invalid cfg, 'sources.latest.file: must name a data file'
  end

  # -- Merged lists ------------------------------------------------------------

  def merged_config(section_overrides = {}, source_overrides = {})
    {
      'sections' => [{ 'type' => 'feed', 'title' => 'Latest',
                       'sources' => %w[pinned blog newsletter], 'limit' => 3 }.merge(section_overrides)],
      'sources' => {
        'pinned' => { 'type' => 'pinned', 'items' => [] },
        'blog' => { 'type' => 'posts', 'label' => 'Blog' },
        'newsletter' => { 'type' => 'data', 'file' => 'newsletter', 'label' => 'Newsletter', 'limit' => 1 },
      }.merge(source_overrides),
    }
  end

  def merged(cfg, data = { 'newsletter' => NEWSLETTER })
    Bio.validate!(cfg)
    Bio.resolve(cfg, POSTS, NOW, SITE, data).first['tiles'].map { |t| [t['label'], t['note']] }
  end

  def test_merged_list_is_newest_first_across_feeds
    assert_equal [['Voice', 'Blog · October 14, 2026'],
                  ['Latest issue', 'Newsletter · October 1, 2026'],
                  ['2026.10', 'Blog · October 1, 2026']],
                 merged(merged_config)
  end

  def test_source_limit_caps_its_items
    # Two newsletter issues exist; the source allows one.
    labels = merged(merged_config('limit' => 10)).map(&:first)
    assert_equal ['Voice', 'Latest issue', '2026.10'], labels
  end

  def test_pin_goes_first_and_the_feeds_continue_below
    cfg = merged_config({}, 'pinned' => { 'type' => 'pinned',
                                           'items' => [{ 'title' => 'Launch', 'url' => '/launch/' }] })
    assert_equal ['Launch', 'Voice', 'Latest issue'], merged(cfg).map(&:first)
  end

  def test_pinned_post_is_not_repeated_from_the_blog
    cfg = merged_config({}, 'pinned' => { 'type' => 'pinned',
                                           'items' => [{ 'title' => 'Voice', 'url' => '/blog/2026/10/14/voice/' }] })
    assert_equal ['Voice', 'Latest issue', '2026.10'], merged(cfg).map(&:first)
  end

  def test_exclude_category
    cfg = merged_config({}, 'blog' => { 'type' => 'posts', 'label' => 'Blog', 'exclude_category' => 'Release-Notes' })
    assert_equal ['Voice', 'Latest issue'], merged(cfg).map(&:first)
  end

  def test_missing_newsletter_leaves_the_blog
    assert_equal ['Voice', '2026.10'], merged(merged_config, {}).map(&:first)
  end

  def test_section_needs_source_or_sources_not_both
    cfg = merged_config('source' => 'blog')
    assert_invalid cfg, 'sections[0]: needs either source'
  end

  def test_unknown_name_in_sources_list
    assert_invalid merged_config('sources' => %w[blog newletter]), 'sections[0].sources: unknown source "newletter"'
  end

  def test_exclude_category_only_on_posts
    cfg = merged_config({}, 'newsletter' => { 'type' => 'data', 'file' => 'newsletter', 'exclude_category' => 'x' })
    assert_invalid cfg, 'sources.newsletter.exclude_category: only works on sources of type posts'
  end

  def test_source_limit_must_be_sensible
    cfg = merged_config({}, 'newsletter' => { 'type' => 'data', 'file' => 'newsletter', 'limit' => 0 })
    assert_invalid cfg, 'sources.newsletter.limit: must be a whole number from 1 to 10'
  end

  # -- Inserted items --------------------------------------------------------

  def test_inserted_item_takes_its_place_by_date
    cfg = merged_config('limit' => 10, 'insert' => [
      { 'title' => 'Community Day', 'url' => 'https://example.test/day/', 'date' => '2026-10-10', 'label' => 'Event' },
    ])
    assert_equal [['Voice', 'Blog · October 14, 2026'],
                  ['Community Day', 'Event · October 10, 2026'],
                  ['Latest issue', 'Newsletter · October 1, 2026'],
                  ['2026.10', 'Blog · October 1, 2026']],
                 merged(cfg)
  end

  def test_newest_inserted_item_becomes_the_hero
    cfg = merged_config('hero' => true, 'insert' => [
      { 'title' => 'Launch', 'url' => 'https://example.test/launch/', 'date' => '2026-10-20', 'image' => 'auto' },
    ])
    tile = Bio.resolve(cfg, POSTS, NOW, SITE, { 'newsletter' => NEWSLETTER }).first['tiles'].first
    assert_equal 'Launch', tile['label']
    assert tile['hero']
    assert_includes tile['image'], 'assets.openhomefoundation.org/opengraph'
  end

  def test_inserted_item_needs_a_date
    cfg = merged_config('insert' => [{ 'title' => 'Undated', 'url' => '/x/' }])
    assert_invalid cfg, 'sections[0].insert[0].date: is required'
  end

  def test_inserted_item_needs_a_valid_date
    cfg = merged_config('insert' => [{ 'title' => 'Bad', 'url' => '/x/', 'date' => '10/11/2026' }])
    assert_invalid cfg, 'sections[0].insert[0].date: "10/11/2026" is not a date'
  end

  # -- Hero card -------------------------------------------------------------

  def hero_tiles(section_overrides = {}, source_overrides = {}, data = { 'newsletter' => NEWSLETTER })
    cfg = merged_config({ 'hero' => true }.merge(section_overrides), source_overrides)
    Bio.validate!(cfg)
    Bio.resolve(cfg, POSTS, NOW, SITE, data).first['tiles']
  end

  def test_first_item_becomes_the_hero_with_its_image
    tiles = hero_tiles
    assert tiles.first['hero']
    assert_equal '/images/voice.jpg', tiles.first['image']
    refute tiles[1]['hero']
  end

  def test_hero_gets_its_image_even_when_the_section_has_no_thumbnails
    tiles = hero_tiles('images' => false)
    assert tiles.first['hero']
    assert_nil tiles[1]['image']
  end

  def test_first_item_without_an_image_stays_a_normal_tile
    pin = { 'type' => 'pinned', 'items' => [{ 'title' => 'No picture', 'url' => '/launch/' }] }
    tiles = hero_tiles({}, 'pinned' => pin)
    assert_equal 'No picture', tiles.first['label']
    refute tiles.first['hero']
  end

  def test_hero_must_be_true_or_false
    assert_invalid merged_config('hero' => 'yes'), 'sections[0].hero: must be true or false'
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
