
/*
  # Create Initial Admin User

  Creates the first admin user account:
  - Email: theber83@gmail.com
  - Password: Butters12345
  - Administrator: true

  Steps:
  1. Insert into auth.users (triggers auto-create a sales row)
  2. Insert auth identity for email provider
  3. Update the auto-created sales row to set administrator = true and fill in name
*/

DO $$
DECLARE
  new_user_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO auth.users (
    id,
    instance_id,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_user_meta_data,
    raw_app_meta_data,
    created_at,
    updated_at,
    role,
    aud
  )
  VALUES (
    new_user_id,
    '00000000-0000-0000-0000-000000000000',
    'theber83@gmail.com',
    crypt('Butters12345', gen_salt('bf')),
    now(),
    '{"first_name": "Admin", "last_name": "User"}'::jsonb,
    '{"provider": "email", "providers": ["email"]}'::jsonb,
    now(),
    now(),
    'authenticated',
    'authenticated'
  );

  INSERT INTO auth.identities (
    id,
    user_id,
    identity_data,
    provider,
    provider_id,
    last_sign_in_at,
    created_at,
    updated_at
  )
  VALUES (
    gen_random_uuid(),
    new_user_id,
    jsonb_build_object('sub', new_user_id::text, 'email', 'theber83@gmail.com'),
    'email',
    new_user_id::text,
    now(),
    now(),
    now()
  );

  UPDATE public.sales
  SET
    first_name = 'Admin',
    last_name = 'User',
    administrator = true,
    disabled = false
  WHERE user_id = new_user_id;
END $$;
