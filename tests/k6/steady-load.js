// Steady request rate through the Gateway, half to the UI and half to the API list endpoint.
// Any response that is not 2xx (or a transport error) fails the run: used while disrupting the cluster.
// Env: BASE_URL (default: the k3d load balancer on the cluster's Docker network), RATE (req/s), DURATION.
import http from 'k6/http';
import { Counter } from 'k6/metrics';

const BASE = __ENV.BASE_URL || 'http://k3d-taskflow-serverlb';
const non2xx = new Counter('non_2xx');

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: Number(__ENV.RATE || 50),
      timeUnit: '1s',
      duration: __ENV.DURATION || '60s',
      // Enough pre-started VUs that a few slow responses do not starve the generator (starting VUs mid-run
      // is slow and shows up as dropped iterations that say more about k6 than about the system).
      preAllocatedVUs: 150,
      maxVUs: 300,
    },
  },
  thresholds: {
    // Pass/fail criterion of the disruption tests: every request answered with a 2xx.
    non_2xx: ['count==0'],
    dropped_iterations: ['count==0'],
    // Reported, not a pass/fail gate: how much latency the disruption added.
    http_req_duration: [{ threshold: 'p(99)<1000', abortOnFail: false }],
  },
  summaryTrendStats: ['p(50)', 'p(95)', 'p(99)', 'max'],
};

export default function () {
  const path = Math.random() < 0.5 ? '/' : '/api/v1/tasks';
  const res = http.get(`${BASE}${path}`, { tags: { name: path }, timeout: '10s' });
  if (res.status < 200 || res.status >= 300) {
    non2xx.add(1);
    console.warn(`non-2xx ${res.status} ${path} at ${new Date().toISOString()} ${res.error || ''}`);
  }
}
