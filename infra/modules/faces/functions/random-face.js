// Viewer-request function for /img/henry-ashton.jpg (cloudfront-js-2.0).
// Rewrites the request to a random face from the pool, faces/000.jpg to faces/NNN.jpg.
// The behaviour doesn't cache, so every request gets a fresh pick. Until the pool is
// uploaded, it serves a neutral placeholder instead.

var FACE_COUNT = ${face_count};

function handler(event) {
  var request = event.request;
  if (FACE_COUNT === 0) {
    request.uri = "/assets/face-placeholder.svg";
    return request;
  }
  var n = Math.floor(Math.random() * FACE_COUNT);
  request.uri = "/faces/" + ("00" + n).slice(-3) + ".jpg";
  return request;
}
