import axios from 'axios';

const { apiHost = '' } = window.konversioConfig || {};
const wootAPI = axios.create({ baseURL: `${apiHost}/` });

export default wootAPI;
