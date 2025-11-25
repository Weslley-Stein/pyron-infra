import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  scenarios: {
    trading_spike: {
      executor: 'constant-arrival-rate',
      rate: 20,
      timeUnit: '1s',       
      duration: '1m',
      preAllocatedVUs: 50,
      maxVUs: 100,
    },
  },
  thresholds: {
    http_req_failed: ['rate<0.01'],
    http_req_duration: ['p(95)<600', 'avg<300'],
  },
};

export default function () {
  const url = 'https://pyron.alwa.ai/api/v1/webhook';
  
  const payload = JSON.stringify({
    ticker: "BTCUSDT",
    action: "buy",
    price: 95000.50,
    timestamp: new Date().toISOString()
  });

  const params = {
    headers: {
      'Content-Type': 'application/json',
    },
  };

  const res = http.post(url, payload, params);

  check(res, {
    'is status 202': (r) => r.status === 202,
  });
}