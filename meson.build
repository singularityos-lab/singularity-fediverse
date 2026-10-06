project('singularity-fediverse', ['vala', 'c'],
  version: '0.1.0',
  meson_version: '>= 0.59.0'
)

i18n = import('i18n')
add_project_arguments('-DGETTEXT_PACKAGE="singularity-fediverse"', language: 'c')
subdir('po')

gtk_dep    = dependency('gtk4')
gee_dep    = dependency('gee-0.8')
gio_dep    = dependency('gio-2.0')
soup_dep   = dependency('libsoup-3.0')
json_dep   = dependency('json-glib-1.0')
secret_dep = dependency('libsecret-1')
posix_dep  = meson.get_compiler('vala').find_library('posix')
math_dep   = meson.get_compiler('c').find_library('m')

libsingularity_dep = dependency('singularity-1.0',
  fallback: ['libsingularity', 'libsingularity_dep']
)

if not meson.is_subproject() and libsingularity_dep.type_name() == 'internal'
  libsingularity_vapi_dir = join_paths(meson.project_build_root(), 'subprojects', 'libsingularity')
  add_project_arguments(['--vapidir=' + libsingularity_vapi_dir], language: 'vala')
endif

core = files('src/html.vala', 'src/model.vala', 'src/oauth.vala', 'src/requests.vala', 'src/drafts.vala')

executable('singularity-fediverse',
  core + files(
    'src/accounts.vala',
    'src/client.vala',
    'src/session.vala',
    'src/widgets.vala',
    'src/timeline.vala',
    'src/compose.vala',
    'src/filters_view.vala',
    'src/unread.vala',
    'src/window.vala',
    'src/app.vala',
  ),
  dependencies: [gtk_dep, gee_dep, gio_dep, soup_dep, json_dep, secret_dep, posix_dep, math_dep, libsingularity_dep],
  install: true
)

test_deps = [gee_dep, gio_dep, json_dep, math_dep]
fixtures = 'FEDIVERSE_FIXTURES=' + meson.current_source_dir() / 'tests' / 'fixtures'

html_test = executable('html-test', core + files('tests/html_test.vala'), dependencies: test_deps)
test('html', html_test)

api_test = executable('api-test', core + files('tests/api_test.vala'), dependencies: test_deps)
test('api', api_test, env: [fixtures])

oauth_test = executable('oauth-test', core + files('src/accounts.vala', 'tests/oauth_test.vala'), dependencies: test_deps + [secret_dep, posix_dep])
test('oauth', oauth_test)

shared_module('fediverse-unread',
  files('plugin/unread_plugin.vala'),
  dependencies: [gtk_dep, json_dep, libsingularity_dep, dependency('libpeas-2')],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'plugins' / 'fediverse-unread'
)
install_data('plugin/fediverse-unread.plugin',
  install_dir: get_option('libdir') / 'singularity' / 'plugins' / 'fediverse-unread'
)

shared_module('singularity-fediverse-widget',
  files('widget/mentions_widget.vala'),
  dependencies: [gtk_dep, json_dep, libsingularity_dep],
  install: true,
  install_dir: get_option('libdir') / 'singularity' / 'widgets'
)
install_data('widget/dev.sinty.fediverse.mentions.widget',
  install_dir: get_option('datadir') / 'singularity' / 'widgets'
)

service_conf = configuration_data()
service_conf.set('bindir', get_option('prefix') / get_option('bindir'))
configure_file(
  input: 'data/dev.sinty.fediverse.service.in',
  output: 'dev.sinty.fediverse.service',
  configuration: service_conf,
  install: true,
  install_dir: get_option('datadir') / 'dbus-1' / 'services'
)

install_data('data/dev.sinty.fediverse.desktop',
  install_dir: get_option('datadir') / 'applications'
)

install_data('data/share-targets/dev.sinty.fediverse.post.ini',
  install_dir: get_option('datadir') / 'singularity' / 'share-targets'
)

install_data('data/icons/dev.sinty.fediverse.svg',
  install_dir: get_option('datadir') / 'icons' / 'hicolor' / 'scalable' / 'apps'
)
