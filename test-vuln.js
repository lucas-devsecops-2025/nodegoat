// Test file with command injection vulnerability
const express = require('express');
const { exec } = require('child_process');
const app = express();

app.get('/ping', (req, res) => {
    const host = req.query.host;
    // Vulnerable: command injection with eval
    eval('console.log("' + host + '")');

    // Vulnerable: command injection with exec
    exec('ping -c 4 ' + host, (error, stdout) => {
        res.send(stdout);
    });
});

app.listen(3000);
