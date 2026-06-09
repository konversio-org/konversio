# The backend CI suite never compiles frontend assets, so the Vite manifest
# (public/vite-test/.vite/manifest.json) does not exist there. Request specs that
# render a layout referencing a Vite entrypoint would otherwise raise
# ViteRuby::MissingEntrypointError and return 500. Stub the Vite tag helpers in
# the test environment so views render without a built manifest.
module ViteTestStubs
  def vite_client_tag(*) = ''
  def vite_javascript_tag(*) = ''
  def vite_typescript_tag(*) = ''
  def vite_stylesheet_tag(*) = ''
end

ActiveSupport.on_load(:action_view) { prepend ViteTestStubs }
