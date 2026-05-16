import axios from 'axios';

const { apiHost = '' } = window.pilotConfig || {};
const wootAPI = axios.create({ baseURL: `${apiHost}/` });

export default wootAPI;
