const { chromium } = require('playwright');
(async () => {
  const b = await chromium.launch();
  const p = await b.newPage();
  await p.goto('file://' + process.argv[2]);
  await p.pdf({ path: process.argv[3], format: 'A4', printBackground: true,
    displayHeaderFooter: true, headerTemplate: '<span></span>',
    footerTemplate: '<div style="width:100%;text-align:center;font-size:7.5pt;color:#8a949c;font-family:Helvetica">Brukermanual Regnskap · Tillerflaten Digital · side <span class="pageNumber"></span> av <span class="totalPages"></span></div>',
    margin: { top: '16mm', bottom: '18mm', left: '16mm', right: '16mm' }, preferCSSPageSize: true });
  await b.close();
})();
