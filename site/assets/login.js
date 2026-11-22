// Sign-in pages. A separate file because the Content-Security-Policy forbids inline
// scripts. Everything here is a convenience: the forms work without JavaScript.
(function () {
  // Show the message for ?expired=1, ?invalid=1 or ?wrong=1.
  var params = new URLSearchParams(window.location.search);
  ["expired", "invalid", "wrong"].forEach(function (name) {
    var message = document.getElementById(name);
    if (message && params.has(name)) {
      message.hidden = false;
    }
  });

  // The code page receives the address in the URL fragment (#email=...), which is never
  // sent to the server. Pre-fill it and move focus to the code.
  var fragment = new URLSearchParams(window.location.hash.slice(1));
  var email = document.getElementById("email");
  var code = document.getElementById("code");
  if (code && email && fragment.get("email")) {
    email.value = fragment.get("email");
    code.focus();
  }
})();
