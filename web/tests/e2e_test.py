# End-to-end test of the EGO FOCUS web app in headless Chrome at iPhone size.
# Usage: python3 e2e_test.py <web-dir> <screenshot-dir>
import asyncio, sys, http.server, threading, functools, os
from playwright.async_api import async_playwright
ROOT = sys.argv[1]; OUT = sys.argv[2]; os.makedirs(OUT, exist_ok=True)
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *a): pass
srv = http.server.ThreadingHTTPServer(("127.0.0.1", 8765), functools.partial(Q, directory=ROOT))
threading.Thread(target=srv.serve_forever, daemon=True).start()
errors = []; results = []
def ok(name, cond):
    results.append((name, bool(cond))); print(("PASS " if cond else "FAIL ") + name)

SWIPE = """([sel, dx]) => { const el = document.querySelector(sel); const r = el.getBoundingClientRect();
  const x = r.left + r.width / 2, y = r.top + r.height / 2;
  const t = (cx) => new Touch({ identifier: 1, target: el, clientX: cx, clientY: y });
  el.dispatchEvent(new TouchEvent('touchstart', { bubbles: true, touches: [t(x)] }));
  for (let i = 1; i <= 8; i++) el.dispatchEvent(new TouchEvent('touchmove', { bubbles: true, touches: [t(x + dx * i / 8)] }));
  el.dispatchEvent(new TouchEvent('touchend', { bubbles: true, touches: [] })); }"""

async def main():
    async with async_playwright() as p:
        b = await p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox"])
        ctx = await b.new_context(viewport={"width": 393, "height": 852}, device_scale_factor=3, is_mobile=True, has_touch=True, locale="ar", timezone_id="Asia/Riyadh")
        pg = await ctx.new_page()
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.on("console", lambda m: errors.append(m.text) if m.type == "error" else None)
        await pg.goto("http://127.0.0.1:8765/index.html"); await pg.wait_for_timeout(700)

        ok("onboarding shown on first launch", await pg.locator(".onb").count() == 1)
        await pg.screenshot(path=f"{OUT}/0-onboarding.png")
        await pg.click("[data-act=onbNext]"); await pg.click("[data-act=onbNext]"); await pg.click("[data-act=onbNext]"); await pg.wait_for_timeout(200)
        ok("onboarding finished", await pg.locator(".onb").count() == 0)
        ok("brand fonts loaded", await pg.evaluate("document.fonts.check('600 20px \"Readex Pro\"') && document.fonts.check('16px \"IBM Plex Sans Arabic\"')"))
        await pg.screenshot(path=f"{OUT}/1-home-empty.png")

        # Quick add sheet with natural-language hint
        await pg.click(".fab"); await pg.wait_for_timeout(300)
        ok("quick add sheet opens", await pg.locator(".sheet.mini #qaTitle").count() == 1)
        await pg.fill("#qaTitle", "اجتماع الفريق بكرة الساعة 10 صباحا"); await pg.wait_for_timeout(150)
        ok("live date hint", await pg.locator("#qaHint .qhint").count() == 1)
        await pg.screenshot(path=f"{OUT}/2-quick-add.png")
        await pg.click("[data-act=qaPrio][data-v=urgent]")
        await pg.click("#qaSave"); await pg.wait_for_timeout(300)
        ok("parsed task added with clean title", await pg.locator(".task .title", has_text="اجتماع الفريق").count() == 1)

        # Quick add plain + more details → full editor
        await pg.click(".fab"); await pg.fill("#qaTitle", "مهمة اختبار الويب"); await pg.click("[data-act=qaMore]"); await pg.wait_for_timeout(200)
        ok("details opens full editor with title", await pg.input_value("[data-f=title]") == "مهمة اختبار الويب")
        await pg.click("[data-act=prio][data-v=high]"); await pg.click("#saveBtn"); await pg.wait_for_timeout(300)
        ok("task created", await pg.locator(".task .title", has_text="مهمة اختبار الويب").count() == 1)

        # Home quick input
        await pg.fill("#quickInput", "مهمة سريعة"); await pg.press("#quickInput", "Enter"); await pg.wait_for_timeout(300)
        ok("quick input add", await pg.locator(".task .title", has_text="مهمة سريعة").count() == 1)

        # Edit
        await pg.click(".task .title >> text=مهمة اختبار الويب"); await pg.fill("[data-f=title]", "مهمة معدلة"); await pg.fill("[data-f=details]", "وصف تجريبي"); await pg.click("#saveBtn"); await pg.wait_for_timeout(300)
        ok("task edited", await pg.locator(".task .title", has_text="مهمة معدلة").count() == 1 and await pg.locator(".details", has_text="وصف تجريبي").count() == 1)

        # Complete via check (animated)
        await pg.click(".task:has-text('مهمة معدلة') .check"); await pg.wait_for_timeout(600)
        ok("task completed", await pg.locator(".task.done .title", has_text="مهمة معدلة").count() == 1)
        await pg.reload(); await pg.wait_for_timeout(600)
        ok("persists after reload (no onboarding again)", await pg.locator(".task.done .title", has_text="مهمة معدلة").count() == 1 and await pg.locator(".onb").count() == 0)

        # Swipe right = reopen, swipe left = delete + undo
        await pg.evaluate(SWIPE, ["[data-swipe] .task.done", 140]); await pg.wait_for_timeout(600)
        ok("swipe right reopens", await pg.locator(".task:not(.done) .title", has_text="مهمة معدلة").count() == 1)
        tid = await pg.locator(".task", has_text="مهمة سريعة").get_attribute("data-id")
        sel = f'[data-swipe="{tid}"] .task'
        await pg.evaluate(SWIPE, [sel, -140]); await pg.wait_for_timeout(600)
        ok("swipe left deletes", await pg.locator(".task .title", has_text="مهمة سريعة").count() == 0)
        ok("undo bar shown", await pg.locator(".undo").count() == 1)
        await pg.screenshot(path=f"{OUT}/3-undo.png")
        await pg.click(".undo button"); await pg.wait_for_timeout(300)
        ok("undo restores", await pg.locator(".task .title", has_text="مهمة سريعة").count() == 1)

        # Assistant
        await pg.click("[data-act=assistant]"); await pg.click(".example >> nth=0"); await pg.wait_for_timeout(250)
        v = await pg.input_value("[data-af=title]"); ok("assistant preview title (" + v + ")", v == "مراجعة الفواتير")
        await pg.screenshot(path=f"{OUT}/5-assistant.png")
        await pg.click("[data-act=assistSave]"); await pg.wait_for_timeout(300)
        ok("assistant task added", await pg.locator(".task .title", has_text="مراجعة الفواتير").count() == 1)
        await pg.click("[data-act=assistant]"); await pg.click(".example >> nth=1"); await pg.wait_for_timeout(250)
        ok("ambiguous blocks save", not await pg.is_enabled("[data-act=assistSave]"))
        await pg.check("[data-af=confirmed]"); await pg.wait_for_timeout(150)
        ok("confirm enables save", await pg.is_enabled("[data-act=assistSave]"))
        await pg.click(".sheet-bar [data-act=close]")

        # Recurring via full editor
        await pg.click(".fab"); await pg.fill("#qaTitle", "مهمة يومية"); await pg.click("[data-act=qaMore]")
        await pg.select_option("[data-f=recurrence]", "daily"); await pg.click("#saveBtn"); await pg.wait_for_timeout(300)
        await pg.click(".task:has-text('مهمة يومية') .check"); await pg.wait_for_timeout(600)
        ok("recurring stays open, not duplicated", await pg.locator(".task .title", has_text="مهمة يومية").count() == 1 and await pg.locator(".task.done .title", has_text="مهمة يومية").count() == 0)
        await pg.screenshot(path=f"{OUT}/1-home.png", full_page=True)

        await pg.click("[data-act=tab][data-v=calendar]"); await pg.wait_for_timeout(300)
        m1 = await pg.inner_text(".cal-head h2"); await pg.click("[data-act=calNext]"); m2 = await pg.inner_text(".cal-head h2"); await pg.click("[data-act=calToday]"); m3 = await pg.inner_text(".cal-head h2")
        ok(f"calendar nav ({m1} → {m2})", m1 != m2 and m1 == m3)
        await pg.screenshot(path=f"{OUT}/6-calendar.png")
        await pg.click("[data-act=tab][data-v=reports]"); await pg.wait_for_timeout(900)
        ok("reports completed count == 1", int(await pg.inner_text(".tile >> nth=0 >> b")) == 1)
        await pg.screenshot(path=f"{OUT}/7-reports.png")

        # Delete from editor + undo
        await pg.click("[data-act=tab][data-v=home]"); await pg.wait_for_timeout(200)
        await pg.click(".task .title >> text=مهمة معدلة"); await pg.click("[data-act=delete]"); await pg.wait_for_timeout(300)
        ok("editor delete (no blocking dialog)", await pg.locator(".task .title", has_text="مهمة معدلة").count() == 0)

        await pg.click("[data-act=tab][data-v=settings]"); await pg.click("[data-act=theme][data-v=dark]"); await pg.wait_for_timeout(300)
        ok("dark theme", await pg.evaluate("document.documentElement.dataset.theme") == "dark")
        await pg.screenshot(path=f"{OUT}/8-settings-dark.png")
        for tab, name in [("home", "9-home-dark"), ("calendar", "10-calendar-dark"), ("reports", "11-reports-dark")]:
            await pg.click(f"[data-act=tab][data-v={tab}]"); await pg.wait_for_timeout(900); await pg.screenshot(path=f"{OUT}/{name}.png")
        await pg.click("[data-act=tab][data-v=home]"); await pg.click(".fab"); await pg.fill("#qaTitle", "تجربة الوضع الداكن"); await pg.wait_for_timeout(200)
        await pg.screenshot(path=f"{OUT}/12-quick-dark.png"); await pg.click(".qa [data-act=close]")
        await pg.click("[data-act=all]"); await pg.wait_for_timeout(250); await pg.screenshot(path=f"{OUT}/13-all-dark.png"); await pg.click(".sheet-bar [data-act=close]")
        ok("RTL", await pg.evaluate("getComputedStyle(document.body).direction") == "rtl")
        ok("no JS errors " + str(errors[:3]), not errors)
        await b.close()
asyncio.run(main()); srv.shutdown()
print(sum(r for _, r in results), "/", len(results))
sys.exit(0 if all(r for _, r in results) else 1)
