// We need to import the CSS so that webpack will load it.
// The MiniCssExtractPlugin is used to separate it out into
// its own CSS file.
import css from "../css/app.css"

// webpack automatically bundles all modules in your
// entry points. Those entry points can be configured
// in "webpack.config.js".
//
// Import dependencies
//
import "phoenix_html"

// Import local files
//
// Local files can be imported directly using relative paths, for example:
// import socket from "./socket"
window.onload = function () {
  let endpointUrlEl = document.getElementById('config_form_endpoint_url_host')
  if (endpointUrlEl) {
    endpointUrlEl.addEventListener('change', function (evt) {
      let endpointUrl = endpointUrlEl.value;

      let adminEmailEl = document.getElementById('config_form_instance_email');
      if (adminEmailEl.value == '') {
        adminEmailEl.value = 'admin@' + endpointUrl;
      }

      let notifyEmailEl = document.getElementById('config_form_instance_notify_email');
      if (notifyEmailEl.value == '') {
        notifyEmailEl.value = 'no-reply@' + endpointUrl;
      }
    });
  }
}
