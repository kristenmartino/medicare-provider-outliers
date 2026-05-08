# Snowflake auth setup

Snowflake enforces MFA for password-only logins on human users. Programmatic clients (dbt, Hex, GitHub Actions) authenticate with **RSA key-pair** auth instead.

## Generate a key pair

```bash
mkdir -p ~/.snowflake/keys && cd ~/.snowflake/keys

# Generate unencrypted PKCS#8 private key (for simplicity).
# For production, generate with -v2 des3 + a passphrase, and use
# private_key_passphrase in profiles.yml.
openssl genrsa 2048 \
  | openssl pkcs8 -topk8 -inform PEM -out dbt_rsa_key.p8 -nocrypt

# Derive the public key
openssl rsa -in dbt_rsa_key.p8 -pubout -out dbt_rsa_key.pub

chmod 600 dbt_rsa_key.p8
chmod 644 dbt_rsa_key.pub
```

## Register the public key with Snowflake

Strip the PEM headers / newlines and paste into an `ALTER USER` statement:

```bash
grep -v 'PUBLIC KEY' ~/.snowflake/keys/dbt_rsa_key.pub | tr -d '\n'
```

Run as `ACCOUNTADMIN` in a Snowsight worksheet (substituting your username and the public-key string from the command above):

```sql
USE ROLE ACCOUNTADMIN;
ALTER USER <YOUR_USERNAME> SET RSA_PUBLIC_KEY='<paste-key-body-here>';
```

## Configure dbt

In `~/.dbt/profiles.yml`:

```yaml
medicare:
  outputs:
    dev:
      type: snowflake
      account: <ACCOUNT>.<REGION>
      user: <YOUR_USERNAME>
      private_key_path: /Users/<you>/.snowflake/keys/dbt_rsa_key.p8
      role: ANALYST
      warehouse: DBT_XS_WH
      database: ANALYTICS
      schema: dbt_dev
      threads: 4
```

Then `dbt debug` from the project directory should report `All checks passed!`.

## CI / GitHub Actions

For CI, store the **contents** of `dbt_rsa_key.p8` as a secret named `SNOWFLAKE_PRIVATE_KEY`, then materialize it to a tmp file at job start. See `.github/workflows/dbt_docs.yml` for the pattern.
