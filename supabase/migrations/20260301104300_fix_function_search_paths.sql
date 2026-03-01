/*
  # Fix function search paths

  Adds SET search_path = '' to all SECURITY DEFINER functions that were
  missing it. Without this, PostgREST schema introspection can fail with
  "Database error querying schema" during authentication.

  Functions fixed:
  - get_user_id_by_email: was missing search_path, causing auth 500 errors
  - set_sales_id_default: was missing search_path
  - get_avatar_for_email: was missing search_path  
  - get_domain_favicon: was missing search_path
  - handle_contact_saved: was missing search_path
  - handle_company_saved: was missing search_path
  - handle_contact_note_created_or_updated: already had it (no change needed)
*/

CREATE OR REPLACE FUNCTION public.get_user_id_by_email(email TEXT)
RETURNS TABLE (id uuid)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  RETURN QUERY SELECT au.id FROM auth.users au WHERE au.email = $1;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.get_user_id_by_email FROM anon, authenticated, public;

CREATE OR REPLACE FUNCTION public.set_sales_id_default()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.sales_id IS NULL THEN
    SELECT id INTO NEW.sales_id FROM public.sales WHERE user_id = auth.uid();
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_domain_favicon(domain_name text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE domain_status int8;
BEGIN
  IF EXISTS (SELECT FROM public.favicons_excluded_domains AS fav WHERE fav.domain = domain_name) THEN
    RETURN null;
  END IF;

  RETURN concat(
    'https://favicon.show/',
    (regexp_matches(domain_name, '^(?:https?:\/\/)?(?:[^@\/\n]+@)?(?:www\.)?([^:\/?\n]+)', 'i'))[1]
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.get_avatar_for_email(email text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE email_hash text;
DECLARE gravatar_url text;
DECLARE gravatar_status int8;
DECLARE email_domain text;
DECLARE favicon_url text;
DECLARE domain_status int8;
BEGIN
  email_hash = encode(extensions.digest(email, 'sha256'), 'hex');
  gravatar_url = concat('https://www.gravatar.com/avatar/', email_hash, '?d=404');

  SELECT status FROM extensions.http_get(gravatar_url) INTO gravatar_status;

  IF gravatar_status = 200 THEN
    RETURN gravatar_url;
  END IF;

  email_domain = split_part(email, '@', 2);
  RETURN public.get_domain_favicon(email_domain);
EXCEPTION
  WHEN others THEN
    RETURN 'ERROR';
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_contact_saved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE contact_avatar text;
DECLARE emails_length int8;
DECLARE item jsonb;
BEGIN
  IF new.avatar IS NOT NULL THEN
    RETURN new;
  END IF;

  SELECT coalesce(jsonb_array_length(new.email_jsonb), 0) INTO emails_length;

  IF emails_length = 0 THEN
    RETURN new;
  END IF;

  FOR item IN SELECT jsonb_array_elements(new.email_jsonb)
  LOOP
    SELECT public.get_avatar_for_email(item->>'email') INTO contact_avatar;
    IF (contact_avatar IS NOT NULL) THEN
      EXIT;
    END IF;
  END LOOP;

  IF contact_avatar IS NULL THEN
    RETURN new;
  END IF;

  new.avatar = concat('{"src":"', contact_avatar, '"}');
  RETURN new;
END;
$$;

CREATE OR REPLACE FUNCTION public.handle_company_saved()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE company_logo text;
BEGIN
  IF new.logo IS NOT NULL THEN
    RETURN new;
  END IF;

  company_logo = public.get_domain_favicon(new.website);
  IF company_logo IS NULL THEN
    RETURN new;
  END IF;

  new.logo = concat('{"src":"', company_logo, '","title":"Company favicon"}');
  RETURN new;
END;
$$;
