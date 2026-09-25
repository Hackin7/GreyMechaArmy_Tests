let rendererReady = false;

self.onmessage = async (event) => {
  const message = event.data ?? {};

  if (message.type === 'INIT') {
    try {
      importScripts(`${message.assetBase}elk-api.js`);
      const ElkApi = self.ELK;
      const elkWorkerUrl = `${message.assetBase}elk-worker.js`;
      self.ELK = class BrowserWorkerELK extends ElkApi {
        constructor(options = {}) {
          super({ ...options, workerUrl: options.workerUrl ?? elkWorkerUrl });
        }
      };
      importScripts(`${message.assetBase}netlistsvg.bundle.js`);
      rendererReady = Boolean(self.netlistsvg?.render && self.netlistsvg?.digitalSkin);
      self.postMessage({ type: rendererReady ? 'READY' : 'ERROR', error: rendererReady ? undefined : 'Netlist renderer failed to initialize.' });
    } catch (error) {
      self.postMessage({ type: 'ERROR', error: error.message || String(error) });
    }
    return;
  }

  if (message.type !== 'RENDER' || !rendererReady) return;

  const { requestId, json, moduleName } = message;
  try {
    const source = JSON.parse(new TextDecoder().decode(json));
    const module = source.modules?.[moduleName];
    if (!module) throw new Error(`Module "${moduleName}" was not found in this netlist.`);

    const netlist = {
      ...source,
      modules: { [moduleName]: module }
    };
    const svg = await self.netlistsvg.render(self.netlistsvg.digitalSkin, netlist);
    if (typeof svg !== 'string' || !svg.startsWith('<svg')) {
      throw new Error('The netlist renderer did not return an SVG diagram.');
    }
    self.postMessage({ type: 'RENDERED', requestId, moduleName, svg });
  } catch (error) {
    self.postMessage({ type: 'RENDER_ERROR', requestId, moduleName, error: error.message || String(error) });
  }
};
