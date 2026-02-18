import { test, expect } from 'playwright/test';

test('editor wiring and shader output', async ({ page }) => {
  const consoleErrors: string[] = [];
  const pageErrors: string[] = [];

  page.on('console', (msg) => {
    if (msg.type() === 'error') consoleErrors.push(msg.text());
  });
  page.on('pageerror', (err) => pageErrors.push(String(err)));

  await page.goto('http://127.0.0.1:8080/', { waitUntil: 'networkidle' });

  const left = page.locator('#jaiInput');
  const right = page.locator('#shaderOutput');

  await expect(left).toBeVisible();
  await expect(right).toBeVisible();

  await left.fill('my_shader :: () { return; }');

  await expect(right).toContainText('#include <metal_stdlib>');
  await expect(right).toContainText('shader_bytes=27');

  expect(pageErrors, `page errors: ${pageErrors.join('\n')}`).toEqual([]);
  expect(consoleErrors, `console errors: ${consoleErrors.join('\n')}`).toEqual([]);
});
