(function () {
  const styles = `
    body {
      margin: 0;
      font-family: Roboto, Arial, sans-serif;
      background: #f9f9f9;
    }
    .blurred {
      filter: blur(6px);
      pointer-events: none;
      user-select: none;
    }
    .bot-check-overlay {
      position: fixed;
      top: 0;
      left: 0;
      width: 100%;
      height: 100%;
      background: rgba(255, 255, 255, 0.95);
      z-index: 9999;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .rc-anchor {
      width: 304px;
      border: 1px solid #d3d3d3;
      background: #fff;
      border-radius: 3px;
      box-shadow: 0 0 5px rgba(0, 0, 0, 0.1);
      font-size: 13px;
    }
    .rc-anchor-content {
      display: flex;
      flex-direction: column;
      padding: 15px;
      align-items: flex-start;
    }
    .rc-anchor-row {
      display: flex;
      align-items: center;
    }
    .recaptcha-checkbox {
      width: 28px;
      height: 28px;
      border: 2px solid #d3d3d3;
      border-radius: 2px;
      background: #fff;
      position: relative;
      cursor: pointer;
      box-shadow: inset 0 1px 1px rgba(0,0,0,0.05);
      transition: border 0.2s ease;
    }
    .recaptcha-checkbox:hover {
      border-color: #a0a0a0;
    }
    .recaptcha-checkbox-checked {
      border-color: #a0a0a0;
    }
    .recaptcha-checkbox-checkmark {
      position: absolute;
      top: 4px;
      left: 7px;
      width: 9px;
      height: 16px;
      transform: rotate(45deg);
      border-right: 3px solid #000;
      border-bottom: 3px solid #000;
      opacity: 0;
      transition: opacity 0.2s ease;
    }
    .recaptcha-checkbox-checked .recaptcha-checkbox-checkmark {
      opacity: 1;
    }
    .rc-anchor-label {
      margin-left: 15px;
      cursor: pointer;
      user-select: none;
      color: #000;
    }
    .rc-anchor-normal-footer {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 8px 15px;
      border-top: 1px solid #e0e0e0;
      font-size: 10px;
      color: #777;
    }
    .rc-anchor-logo-img-portrait {
      width: 32px;
      height: 32px;
      background: url('https://www.gstatic.com/recaptcha/api2/logo_48.png') no-repeat center center;
      background-size: contain;
    }
    .rc-anchor-logo-text {
      margin-top: 4px;
    }
    .rc-anchor-pt a {
      color: #555;
      text-decoration: none;
      font-size: 10px;
    }
    .rc-anchor-pt a:hover {
      text-decoration: underline;
    }
    .loading-dots {
      margin-top: 10px;
      font-size: 12px;
      color: #777;
    }
    .loading-dots::after {
      content: '.';
      animation: dots 1.5s steps(3, end) infinite;
    }
    @keyframes dots {
      0% { content: '.'; }
      33% { content: '..'; }
      66% { content: '...'; }
    }
  `;

  const styleTag = document.createElement('style');
  styleTag.textContent = styles;
  document.head.appendChild(styleTag);

  const content = document.getElementById('page-content');
  if (content) content.classList.add('blurred');

  const overlay = document.createElement('div');
  overlay.className = 'bot-check-overlay';
  overlay.id = 'botCheck';
  overlay.innerHTML = `
    <div class="rc-anchor">
      <div class="rc-anchor-content">
        <div class="rc-anchor-row">
          <div class="recaptcha-checkbox" id="recaptchaCheckbox" role="checkbox" aria-checked="false" tabindex="0">
            <div class="recaptcha-checkbox-checkmark"></div>
          </div>
          <label for="recaptchaCheckbox" class="rc-anchor-label">I'm not a robot</label>
        </div>
        <div id="loadingText" class="loading-dots" style="display: none;">Verifying</div>
      </div>
      <div class="rc-anchor-normal-footer">
        <div class="rc-anchor-logo-portrait" aria-hidden="true" role="presentation">
          <div class="rc-anchor-logo-img rc-anchor-logo-img-portrait"></div>
          <div class="rc-anchor-logo-text">reCAPTCHA</div>
        </div>
        <div class="rc-anchor-pt">
          <a href="https://www.google.com/intl/en/policies/privacy/" target="_blank">Privacy</a>
          <span aria-hidden="true" role="presentation"> - </span>
          <a href="https://www.google.com/intl/en/policies/terms/" target="_blank">Terms</a>
        </div>
      </div>
    </div>
  `;

  document.body.appendChild(overlay);

  const checkbox = overlay.querySelector('#recaptchaCheckbox');
  const loadingText = overlay.querySelector('#loadingText');

  checkbox.addEventListener('click', () => {
    if (checkbox.classList.contains('recaptcha-checkbox-checked')) return;

    checkbox.classList.add('recaptcha-checkbox-checked');
    checkbox.setAttribute('aria-checked', 'true');
    loadingText.style.display = 'block';

    const waitTime = (Math.random() * (2.5 - 1.0) + 1.0) * 1000;

    setTimeout(() => {
      overlay.style.display = 'none';
      if (content) content.classList.remove('blurred');

      const randHash = Array.from(crypto.getRandomValues(new Uint8Array(16)))
        .map(b => b.toString(16).padStart(2, '0')).join('');
      document.cookie = \`not_bot=\${randHash}; path=/; max-age=3600\`;
    }, waitTime);
  });
})();
