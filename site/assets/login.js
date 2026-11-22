// Shows the message for ?expired=1 or ?invalid=1 on the sign-in page. A separate file
// because the Content-Security-Policy forbids inline scripts.
(function () {
  var params = new URLSearchParams(window.location.search);
  ["expired", "invalid"].forEach(function (name) {
    if (params.has(name)) {
      document.getElementById(name).hidden = false;
    }
  });
})();
