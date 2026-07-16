import jenkins.model.*
import hudson.security.*
import jenkins.security.s2m.AdminWhitelistRule
import hudson.security.csrf.DefaultCrumbIssuer

// ── The Last Jenkins Job — Auto-Configuration ─────────────────────
// Jenkins bootstraps itself so it can immediately get to work
// on its own obsolescence.

def instance = Jenkins.getInstance()

// ── Admin user ────────────────────────────────────────────────────
def hudsonRealm = new HudsonPrivateSecurityRealm(false)
hudsonRealm.createAccount('admin', 'admin')
instance.setSecurityRealm(hudsonRealm)

def strategy = new FullControlOnceLoggedInAuthorizationStrategy()
strategy.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(strategy)

// ── CSRF protection (keep it on, we're not savages) ───────────────
instance.setCrumbIssuer(new DefaultCrumbIssuer(true))

// ── Agent → Controller security ───────────────────────────────────
instance.getInjector()
    .getInstance(AdminWhitelistRule.class)
    .setMasterKillSwitch(false)

// ── Number of executors on the controller ─────────────────────────
// We only need enough to run one last job
instance.setNumExecutors(2)

// ── Location config ───────────────────────────────────────────────
def locationConfig = JenkinsLocationConfiguration.get()
locationConfig.setUrl('http://localhost:8080/')
locationConfig.setAdminAddress('jenkins@last-jenkins-job.local')
locationConfig.save()

instance.save()

println("Jenkins has configured itself and is ready to begin its final mission.")
