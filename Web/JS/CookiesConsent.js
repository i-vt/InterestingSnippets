(function() {
  const style = document.createElement('style');
  style.textContent = `
    #cookie-consent {
      position: fixed;
      bottom: 20px;
      right: 20px;
      background-color: red;
      color: white;
      padding: 15px;
      border-radius: 8px;
      z-index: 1000;
      font-family: Arial, sans-serif;
      box-shadow: 0 4px 8px rgba(0,0,0,0.2);
    }
    #cookie-consent button {
      margin: 5px;
      padding: 5px 10px;
      border: none;
      cursor: pointer;
      border-radius: 4px;
    }
    #cookie-consent .accept {
      background-color: #4CAF50;
      color: white;
    }
    #cookie-consent .decline {
      background-color: #f44336;
      color: white;
    }
  `;
  document.head.appendChild(style);

  const consent = localStorage.getItem("cookie_consent");

  if (!consent) {
    const consentBox = document.createElement("div");
    consentBox.id = "cookie-consent";
    consentBox.innerHTML = `
      <div>
        We use cookies to improve your experience.<br>
        Do you accept?
      </div>
      <button class="accept">Accept</button>
      <button class="decline">Decline</button>
    `;

    document.body.appendChild(consentBox);

    consentBox.querySelector(".accept").addEventListener("click", () => {
      localStorage.setItem("cookie_consent", "accepted");
      consentBox.remove();
    });

    consentBox.querySelector(".decline").addEventListener("click", () => {
      localStorage.setItem("cookie_consent", "declined");
      consentBox.remove();
    });
  }
})();
