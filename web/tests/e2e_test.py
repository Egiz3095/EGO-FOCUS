import asyncio, sys, http.server, threading, functools, os
from playwright.async_api import async_playwright
ROOT=sys.argv[1]; OUT=sys.argv[2]; os.makedirs(OUT, exist_ok=True)
class Q(http.server.SimpleHTTPRequestHandler):
    def log_message(self,*a): pass
srv=http.server.ThreadingHTTPServer(("127.0.0.1",8765),functools.partial(Q, directory=ROOT)); threading.Thread(target=srv.serve_forever,daemon=True).start()
errors=[]; results=[]
def ok(name,cond):
    results.append((name,bool(cond))); print(("PASS " if cond else "FAIL ")+name)
async def main():
    async with async_playwright() as p:
        b=await p.chromium.launch(executable_path="/usr/bin/google-chrome", args=["--no-sandbox"])
        ctx=await b.new_context(viewport={"width":393,"height":852}, device_scale_factor=3, is_mobile=True, has_touch=True, locale="ar", timezone_id="Asia/Riyadh")
        await ctx.add_init_script("Date.now = (()=>{const real=Date.now; return real;})();")
        pg=await ctx.new_page()
        pg.on("pageerror", lambda e: errors.append(str(e)))
        pg.on("console", lambda m: errors.append(m.text) if m.type=="error" else None)
        await pg.goto("http://127.0.0.1:8765/index.html"); await pg.wait_for_timeout(600)
        ok("home renders", await pg.locator("text=ركّز على ما يهمك.").count()>0)
        await pg.screenshot(path=f"{OUT}/1-home-empty.png")
        # create via FAB
        await pg.click(".fab"); await pg.fill("[data-f=title]","مهمة اختبار الويب"); 
        await pg.click("[data-act=prio][data-v=urgent]"); await pg.click("#saveBtn"); await pg.wait_for_timeout(200)
        ok("task created", await pg.locator(".task .title", has_text="مهمة اختبار الويب").count()==1)
        # quick add
        await pg.fill("#quickInput","مهمة سريعة"); await pg.press("#quickInput","Enter"); await pg.wait_for_timeout(200)
        ok("quick add", await pg.locator(".task .title", has_text="مهمة سريعة").count()==1)
        # edit
        await pg.click(".task .title >> text=مهمة اختبار الويب"); await pg.fill("[data-f=title]","مهمة معدلة"); await pg.fill("[data-f=details]","وصف تجريبي"); await pg.click("#saveBtn"); await pg.wait_for_timeout(200)
        ok("task edited", await pg.locator(".task .title", has_text="مهمة معدلة").count()==1 and await pg.locator(".details", has_text="وصف تجريبي").count()==1)
        # complete
        await pg.click(".task:has-text('مهمة معدلة') .check"); await pg.wait_for_timeout(200)
        ok("task completed", await pg.locator(".task.done .title", has_text="مهمة معدلة").count()==1)
        # persistence via reload
        await pg.reload(); await pg.wait_for_timeout(500)
        ok("persists after reload", await pg.locator(".task.done .title", has_text="مهمة معدلة").count()==1)
        # reopen
        await pg.click(".task.done:has-text('مهمة معدلة') .check"); await pg.wait_for_timeout(200)
        ok("reopened", await pg.locator(".task:not(.done) .title", has_text="مهمة معدلة").count()==1)
        # assistant
        await pg.click("[data-act=assistant]"); await pg.click(".example >> nth=0"); await pg.wait_for_timeout(200)
        v=await pg.input_value("[data-af=title]"); ok("assistant preview title = مراجعة الفواتير ("+v+")", v=="مراجعة الفواتير")
        await pg.screenshot(path=f"{OUT}/5-assistant.png")
        ok("assistant save enabled for clear command", await pg.is_enabled("[data-act=assistSave]"))
        await pg.click("[data-act=assistSave]"); await pg.wait_for_timeout(200)
        ok("assistant task added", await pg.locator(".task .title", has_text="مراجعة الفواتير").count()==1)
        # ambiguous
        await pg.click("[data-act=assistant]"); await pg.click(".example >> nth=1"); await pg.wait_for_timeout(200)
        ok("ambiguous blocks save", not await pg.is_enabled("[data-act=assistSave]"))
        await pg.check("[data-af=confirmed]"); await pg.wait_for_timeout(150)
        ok("confirm enables save", await pg.is_enabled("[data-act=assistSave]"))
        await pg.click(".sheet-bar [data-act=close]")
        # recurring task + calendar
        await pg.click(".fab"); await pg.fill("[data-f=title]","مهمة يومية"); await pg.select_option("[data-f=recurrence]","daily"); await pg.click("#saveBtn"); await pg.wait_for_timeout(200)
        await pg.click(".task:has-text('مهمة يومية') .check"); await pg.wait_for_timeout(200)
        ok("recurring stays open, not duplicated", await pg.locator(".task .title", has_text="مهمة يومية").count()==1 and await pg.locator(".task.done .title", has_text="مهمة يومية").count()==0)
        await pg.screenshot(path=f"{OUT}/1-home.png", full_page=True)
        await pg.click("[data-act=tab][data-v=calendar]"); await pg.wait_for_timeout(200)
        m1=await pg.inner_text(".cal-head h2"); await pg.click("[data-act=calNext]"); m2=await pg.inner_text(".cal-head h2"); await pg.click("[data-act=calToday]"); m3=await pg.inner_text(".cal-head h2")
        ok(f"calendar nav ({m1} → {m2})", m1!=m2 and m1==m3)
        ok("calendar dots", await pg.locator(".day .dot.p-urgent, .day .dot.p-normal").count()>0)
        await pg.screenshot(path=f"{OUT}/2-calendar.png")
        await pg.click("[data-act=tab][data-v=reports]"); await pg.wait_for_timeout(200)
        ok("reports completed count == 1", int(await pg.inner_text(".tile >> nth=0 >> b"))==1)
        await pg.screenshot(path=f"{OUT}/3-reports.png")
        await pg.click("[data-act=tab][data-v=settings]"); await pg.click("[data-act=theme][data-v=dark]"); await pg.wait_for_timeout(200)
        ok("dark theme", await pg.evaluate("document.documentElement.dataset.theme")=="dark")
        await pg.screenshot(path=f"{OUT}/4-settings-dark.png")
        await pg.click("[data-act=tab][data-v=home]"); await pg.wait_for_timeout(200); await pg.screenshot(path=f"{OUT}/6-home-dark.png")
        # delete
        pg.on("dialog", lambda d: asyncio.ensure_future(d.accept()))
        await pg.click(".task .title >> text=مهمة معدلة"); await pg.click("[data-act=delete]"); await pg.wait_for_timeout(300)
        ok("deleted", await pg.locator(".task .title", has_text="مهمة معدلة").count()==0)
        await pg.click("[data-act=all]"); await pg.wait_for_timeout(200); await pg.screenshot(path=f"{OUT}/7-all.png"); await pg.click(".sheet-bar [data-act=close]")
        await pg.click(".fab"); await pg.wait_for_timeout(200); await pg.screenshot(path=f"{OUT}/8-editor-dark.png")
        ok("RTL", await pg.evaluate("getComputedStyle(document.body).direction")=="rtl")
        ok("no JS errors "+str(errors[:3]), not errors)
        await b.close()
asyncio.run(main()); srv.shutdown()
print(sum(r for _,r in results),"/",len(results))
