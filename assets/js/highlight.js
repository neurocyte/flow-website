function addLineNumbersToPre() {
  const preElements = document.querySelectorAll('div.line-numbers-js  pre ');

  preElements.forEach(pre => {
    const codeBlock = pre.querySelector('code');
    if (!codeBlock) return;
    const htmlContent = codeBlock.innerHTML;
    const lines = htmlContent.split('\n');
    const fragment = document.createDocumentFragment();

    lines.forEach(lineHtml => {
      if (lineHtml.length > 0) {
        const lineWrapper = document.createElement('span');
        lineWrapper.className = "ln";
        lineWrapper.innerHTML = lineHtml;
        fragment.appendChild(lineWrapper);
      }
    });
    codeBlock.innerHTML = '';
    codeBlock.appendChild(fragment);
  });
}
