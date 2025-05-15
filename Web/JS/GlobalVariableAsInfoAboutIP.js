// Get User IP
const url = 'https://api.db-ip.com/v2/free/self/';
let userIpData = {};

async function getUserIp() {
    try {
        const response = await fetch(url);
        if (response.ok) {
            const data = await response.json();
            userIpData = {
                user_ip: data.ipAddress,
                country: data.countryName,
                country_code: data.countryCode
            };
        } else {
            userIpData = {
                user_ip: 'IP not detected ;(',
                country: '-',
                country_code: '-'
            };
        }
    } catch (error) {
        console.error('Error fetching IP:', error);
        userIpData = {
            user_ip: 'IP fetch error',
            country: '-',
            country_code: '-'
        };
    }
}

getUserIp();
