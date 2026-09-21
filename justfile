# App-owned. Runtime recipes come from Tooling/.
import 'Tooling/justfile'

# The demo recipes run only on OneCart's own run device (`just env`). They used to
# copy the build to every booted simulator, which installed OneCart on other
# projects' devices.

# Launches the seeded demo cart (role: owner or member) on OneCart's run device.
demo role="owner":
    just run-sim -- -oneCartDemoUI -oneCartDemoRole {{role}}

# Launches the demo on one tab (cart, history or account) on OneCart's run device.
demo-tab role="owner" tab="cart":
    just run-sim -- -oneCartDemoUI -oneCartDemoRole {{role}} -oneCartDemoTab {{tab}}
