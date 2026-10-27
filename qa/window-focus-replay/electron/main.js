const { app, BrowserWindow, screen } = require('electron');
const focus = require('./focus.node');
const sleep = ms => new Promise(resolve => setTimeout(resolve, ms));
const html = `<!doctype html><body style="margin:0"><button style="position:fixed;inset:0;width:100%;height:100%">Local Chromium focus test</button><script>window.edges={mousedown:0,mouseup:0,click:0};for(const key of Object.keys(edges))document.addEventListener(key,()=>edges[key]++,true);</script>`;

app.whenReady().then(async () => {
  const bounds = screen.getPrimaryDisplay().bounds;
  const windows = [
    new BrowserWindow({ x: 120, y: 160, width: 720, height: 480, title: 'Framed focus test' }),
    new BrowserWindow({ ...bounds, frame: false, title: 'Borderless focus test' }),
  ];
  try {
    for (const win of windows) await win.loadURL('data:text/html;charset=utf-8,' + encodeURIComponent(html));
    await sleep(150);
    let focusFailures = 0;
    for (let index = 0; index < 24; index++) {
      const win = windows[index % windows.length];
      windows[(index + 1) % windows.length].focus();
      await sleep(15);
      focus.post(win.getNativeWindowHandle());
      await sleep(15);
      if (!win.isFocused()) focusFailures++;
    }
    const results = [];
    for (const win of windows) results.push(await win.webContents.executeJavaScript('window.edges'));
    console.log(JSON.stringify({ electron: process.versions.electron, chromium: process.versions.chrome, cycles: 24, focusFailures, results }));
    process.exitCode = focusFailures || results.some(edges => Object.values(edges).some(value => value !== 0)) ? 1 : 0;
  } catch (error) {
    console.error(error.stack);
    process.exitCode = 2;
  } finally {
    for (const win of windows) win.destroy();
    app.exit(process.exitCode || 0);
  }
});
