// Viewer-request function for the S3 behaviours (cloudfront-js-2.0).
//  1. Redirects the apex domain to the canonical www host, keeping path and query.
//  2. Redirects /roles to /roles/, so it reaches the protected behaviour rather than the
//     public bucket (where it would only ever be a 404).
//  3. Maps directory-style URLs to index.html, which an S3 REST origin won't do itself.

var APEX = "${apex_domain}";
var CANONICAL = "${canonical_domain}";

function queryString(querystring) {
  var parts = [];
  Object.keys(querystring).forEach(function (key) {
    var entry = querystring[key];
    var values = entry.multiValue
      ? entry.multiValue.map(function (item) { return item.value; })
      : [entry.value];
    values.forEach(function (value) {
      parts.push(value === "" ? key : key + "=" + value);
    });
  });
  return parts.length ? "?" + parts.join("&") : "";
}

function handler(event) {
  var request = event.request;
  var host = request.headers.host ? request.headers.host.value : "";

  if (host === APEX) {
    return {
      statusCode: 301,
      statusDescription: "Moved Permanently",
      headers: {
        location: { value: "https://" + CANONICAL + request.uri + queryString(request.querystring) },
      },
    };
  }

  var uri = request.uri;
  if (uri === "/roles") {
    return {
      statusCode: 301,
      statusDescription: "Moved Permanently",
      headers: { location: { value: "/roles/" } },
    };
  }

  if (uri.endsWith("/")) {
    request.uri = uri + "index.html";
  } else if (uri.split("/").pop().indexOf(".") === -1) {
    request.uri = uri + "/index.html";
  }
  return request;
}
