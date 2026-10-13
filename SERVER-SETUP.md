# Connecting Field Notes to a shared server

Until a server is connected, Field Notes saves notes and photos **on the computer it runs on**.
To let the whole team see the same notes, connect it to a free Supabase project. This takes
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
- the notes, replies, projects and people tables
- a private photo storage area
- the permission rules:
  - only approved people can see anything
  - people only see projects they belong to
  - only the issuer or an admin can change status or priority
  - only an admin can deactivate a note

## 3. Sign-up settings

Open **Authentication > Sign In / Providers > Email**:

- Leave **Enable email provider** on.
- Turn **Confirm email** *off*. Admins already approve every account in the app, so email
  confirmation is not needed. If you keep it on, people must click a link in an email before
  their first sign-in.

## 4. Connect the app

Copy two values from the Supabase dashboard:
- **Project URL**, under **Project Settings > Data API**. It looks like `https://abcdefgh.supabase.co`.
- **Publishable key**, under **Project Settings > API Keys**. It starts with `sb_publishable_`. The older
  **anon public** key (starting with `eyJ`) also works.

You can connect the app in one of two ways:

- **On one computer:** open Field Notes, go to **Settings > Server connection** (or the server
  icon on the sign-in screen), paste both values, then close and reopen the app.
- **Built into the installer (recommended for the team):** in GitHub open this repository's
  **Settings > Secrets and variables > Actions > New repository secret** and add:
  - `SUPABASE_URL` = the Project URL
  - `SUPABASE_ANON_KEY` = the publishable key

  The next installer GitHub builds connects automatically, so nobody has to type anything.

## 5. First sign-in

1. Open the app and choose **Request access**.
2. Enter your name, work email and a password.
3. **The first account on a new server automatically becomes the admin.**
4. Create the first project (for example *Newcastle Medical Center*).
5. When teammates request access, they appear under **Admin > People**. Approve them and add
   them to their projects there.
