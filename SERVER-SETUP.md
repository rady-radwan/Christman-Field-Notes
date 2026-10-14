# Connecting Field Observations to a shared server

Until a server is connected, Field Observations saves observations and photos **on the computer it runs on**.
To let the whole team see the same observations, connect it to a free Supabase project. This takes
about 10 minutes and is done once, by an admin.

> Before putting real project data on it, check with Christman IT that a hosted service is OK.
> The app can be moved to company hosting later. Nothing in the app depends on who hosts it.

## 1. Create the Supabase project

1. Go to <https://supabase.com> and sign up. A work email is best.
2. Click **New project** and set:
   - **Name**: `christman-field-notes`
   - **Database password**: click *Generate* and keep it somewhere safe.
   - **Region**: the one closest to your sites (for example *East US*).
3. Wait about 2 minutes for the project to start.

## 2. Create the tables and security rules

1. In the left menu open **SQL Editor**, then click **New query**.
2. Open [`supabase/schema.sql`](supabase/schema.sql) from this repository, copy everything, and paste it in.
3. Click **Run**. You should see "Success. No rows returned".

The script creates:
- the observations, discussion, projects, people and member-request tables
- a private storage area for photos and voice messages
- observation numbers (project abbreviation, category abbreviation, serial number, e.g. NCMC-MEP-001)
- the permission rules:
  - people only see projects they are on (admins see all; an admin can let guests view a project)
  - project members can suggest new members; an admin approves them in the app
  - only the reporter or an admin can change status or priority

**Already set up before version 0.7?** Run [`supabase/update-2-observations.sql`](supabase/update-2-observations.sql)
the same way instead. It keeps everything and converts old statuses
(Active → Open, Suspended → On Hold, Solved → Resolved, Deactivated → Voided).

## 3. Sign-in by email code

People sign in by typing their email and then a code that arrives by email. Nobody needs a password.

1. **Send a code instead of a link.** Open **Authentication > Emails** and pick the **Magic Link**
   template. Replace its body with this, then click **Save**:
   ```html
   <h2>Your Field Observations sign-in code</h2>
   <p>Enter this code in the app: <strong>{{ .Token }}</strong></p>
   <p>Or <a href="{{ .ConfirmationURL }}">click here to open Field Observations</a> on the computer where you asked for the code.</p>
   <p>It expires in one hour. If you did not ask for it, ignore this email.</p>
   ```
   Do the same for the **Confirm signup** template.
2. **Make the email link open the app.** Open **Authentication > URL Configuration** and:
   - set **Site URL** to `christman-fieldnotes://login-callback`
   - under **Redirect URLs**, click **Add URL** and add `christman-fieldnotes://login-callback`

   The Windows installer registers this address, so clicking the link opens Field Observations and signs
   the person in. Company mail scanners sometimes use up links before people click them; the code
   always works.
3. **Let the server email everyone.** Supabase's built-in mailer only sends to members of your
   Supabase team, and only a few emails per hour. For the whole project team, connect your own
   mail service under **Authentication > Emails > SMTP Settings**:
   - **Option A:** ask Christman IT for an SMTP account (Microsoft 365 can provide one).
   - **Option B:** use a free sending service such as Brevo, Resend or SendGrid.

   After that, raise the hourly limit under **Authentication > Rate Limits** if needed.

## 4. Connect the app

Copy two values from the Supabase dashboard:
- **Project URL**, under **Project Settings > Data API**. It looks like `https://abcdefgh.supabase.co`.
- **Publishable key**, under **Project Settings > API Keys**. It starts with `sb_publishable_`. The older
  **anon public** key (starting with `eyJ`) also works.

You can connect the app in one of two ways:

- **On one computer:** open Field Observations, go to **Settings > Server connection** (or the server
  icon on the sign-in screen), paste both values, then close and reopen the app.
- **Built into the installer (recommended for the team):** in GitHub open this repository's
  **Settings > Secrets and variables > Actions > New repository secret** and add:
  - `SUPABASE_URL` = the Project URL
  - `SUPABASE_ANON_KEY` = the publishable key

  The next installer GitHub builds connects automatically, so nobody has to type anything.

## 5. First sign-in

1. Open the app, click **Sign in**, enter your work email and click **Email me a sign-in code**.
2. Type the code from the email, then your name.
3. **The first account on a new server automatically becomes the admin.**
4. Create the first project (for example *Newcastle Medical Center*).
5. When teammates request access, they appear under **Admin > People**. Approve them and add
   them to their projects there.
