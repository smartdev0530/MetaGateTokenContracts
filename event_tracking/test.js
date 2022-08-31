// import Web3 from "web3";
const Web3 = require("web3");
const contractABI = require("./ft_abi.json");

// const web3 = new Web3('wss://mainnet.infura.io/ws/v3/87f68694263249fcacd339d8fd6b08b7');
const web3 = new Web3("http://172.30.77.160:8545");
// const web3 = new Web3(new Web3.providers.WebsocketProvider('ws://172.30.77.160:8546'));
// console.log('web3 created', web3);
web3.eth.getChainId().then(console.log);

const myContract = new web3.eth.Contract(
  contractABI,
  "0xf25186B5081Ff5cE73482AD761DB0eB0d25abfBF"
);

myContract
  .getPastEvents("allEvents", function (error, events) {
    console.log(events);
  })
  .then(function (events) {
    console.log(events); // same results as the optional callback above
  });

// var subscription = web3.eth.subscribe('logs', function (error, result) {
//     if (!error)
//         console.log('websocket err', result);
//     console.log('websocket result', result);
// })
//     .on("data", function (log) {
//         console.log(log);
//     })
//     .on("changed", function (log) {
//     });

// // unsubscribes the subscription

// subscription.unsubscribe(function (error, success) {
//     if (success)
//         console.log('Successfully unsubscribed!');
// });

// var options = {
//     fromBlock: 0,
//     toBlock: "latest",
//     // address: "0x25f000254108a104A7127B5a5697cb3C12643e62",
//   };
//   console.log(web3.eth.filter);
//   console.log(web3.eth)
//   var filter = web3.eth.filter(options);

//   filter.get(function(error, result){
//     if (!error)
//       console.log(JSON.stringify(result, null, 2));
//   });
