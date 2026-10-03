# Orthanc Configuration Repository

This repository is for configuration management to orchestrate containers to host an Orthanc service. There are two modes:
1. `DEV` mode: for hosting Orthanc services in a local development environment such as laptop (Linux/MacOS).
2. `AWS` mode: for hosting Orthanc services on EC2 instances provisioned in the [Orthweb](https://github.com/digihunch/orthweb) project. 

The two modes are different in terms of how data store are implemented, as outlined below.

| Component              | DEV mode | AWS mode |
| :---------------- | :------: | ----: |
| Orthanc Database |  local PostgreSQL container   | RDS PostgreSQL |
| Keycloak Database |  local PostgreSQL container   | RDS PostgreSQL |
| Storage    |  data directory   | S3 bucket |
| Default Site URL |  localhost   | EC2 Public DNS name |

The configuration is driven by a `makefile` that orchestrate the steps required in each scenario.

## Configure DEV mode on a Laptop (MacOS or Linux)
Use this mode for development work for customization scripts (e.g. server-side scripting) on a development environment such as Laptop (MacOS/Linux):

1. Clone this repository. It should be cloned to the current user directory:
      ```sh
      git clone git@github.com:digihunchinc/orthanc-config.git
      ```

2. Ensure the required packages are installed. Check `dep` and `dep_ec2` steps for the specific required packages being examined;
3. Modify `.env` file to update any username, passwords and image references. Do not use the original password! 
4. Go to the project directory, execute the steps for `dev`: 

      ```sh
      make dev
      ```
      The command should generate `docker-compose.yaml` file based on the variables in `.env` file.

5. Run the following command to bootstrap for the first time, and ensure to monitor the standard output.

      ```sh
      docker compose up
      ```

      When the launch is nearly completed, the standard output from `keycloak-service` should display a line saying:

      ```
      2024-12-21 23:20:49 ########################################################################################
      Here is the secret to use for the KEYCLOAK_CLIENT_SECRET env var in the auth service:
      qzwffmsgeerdaiglowfhwjxhsotbzrdn
      ########################################################################################
      ```
      Keep a copy of the `KEYCLOAK_CLIENT_SECRET` value. 

6. Go to `docker-compose.yaml` under the environment variables for `orthanc-auth-service`, fill in the `KEYCLOAK_CLIENT_SECRET` value. For example:
      ```sh
      KEYCLOAK_CLIENT_SECRET: "qzwffmsgeerdaiglowfhwjxhsotbzrdn"
      ENABLE_KEYCLOAK_API_KEYS: "true"    # uncomment after bootstrapping
      ```
      Make sure to have both lines uncommented.

6. Then restart services one more time until all services are up:

      ```sh
      docker compose down && docker compose up -d
      ```
Note, when the services are launched, the standard output for `keycloak-backend` may show the following warning:
      
```
2025-01-26 20:28:18 keycloak-backend       | 2025-01-27 01:28:18,640 WARN  [org.keycloak.events] (executor-thread-1) type="CLIENT_LOGIN_ERROR", realmId="51f8e56b-3df7-4a0e-ae5b-4f961f4a3e78", realmName="orthanc", clientId="admin-cli", userId="null", ipAddress="127.0.0.1", error="invalid_client_credentials", grant_type="client_credentials"
2025-01-26 20:28:18 keycloak-backend       | ### Access denied with the default secret, probably already regenerated. Exiting script...
```

This is normal.

Once launched, the services are exposed on localhost on port 443. The configuration requires using full domain name, such as:
- For Orthanc login: https://orthweb.digihunch.com/orthanc 
- For User Admin: https://orthweb.digihunch.com/keycloak 

Note that using `localhost` as domain name will NOT work. As a workaround, consider editing hosts file `/etc/hosts`, by adding an entry `127.0.0.1 orthweb.digihunch.com`, and bypass browser warnings.

## Configure AWS mode on an EC2 instance

Use this mode for test or production environment an EC2 instance. The configuration should be highly automated, drven by the cloud init script. 

For example, the step to clone the repo, and the step to update variables in `.env` are both to be implemented in the cloud init [script](https://github.com/digihunch/orthweb/blob/main/terraform/modules/ec2/userdata2.tpl). 

The script will then execute a command as defined in the input variable of the Terraform template, which is by default:
```sh
cd orthanc-config && make aws
```

If the result isn't expected, review the cloud init log at `/var/log/cloud-init-output.log` on the EC2 instance.

## Certificado Let's Encrypt para nginx-proxy (cron de renovación)

`nginx-proxy` lee un único archivo (`$SITE_KEY_CERT_FILE`, montado como `site.pem`) con la clave privada y la cadena concatenadas. Para usar Let's Encrypt en lugar del certificado autofirmado:

1. Emisión inicial en el host (modo standalone: requiere el puerto 80 abierto hacia afuera; el compose no lo usa):
      ```sh
      sudo certbot certonly --standalone -d $SITE_NAME
      sudo ./scripts/install-cert.sh
      ```
      `install-cert.sh` arma el pem en `$SITE_KEY_CERT_FILE` y hace `nginx -s reload` en el contenedor.

2. Instalar el cron (editar `REPO_DIR` en el archivo si el repo no está en `/home/ubuntu/orthanc-config`):
      ```sh
      sudo cp config/cron/nginx-cert-renew /etc/cron.d/
      sudo chmod 644 /etc/cron.d/nginx-cert-renew
      ```
      Corre `scripts/renew-cert.sh` dos veces por día; certbot sólo renueva cuando faltan menos de 30 días y en ese caso ejecuta `install-cert.sh` como deploy-hook. Log en `/var/log/nginx-cert-renew.log`.

3. Probar sin emitir nada: `sudo certbot renew --dry-run`.

Si el paquete de certbot ya trae su propio timer de systemd (`systemctl list-timers | grep certbot`), alcanza con enlazar el hook en vez de instalar el cron: `sudo ln -s $PWD/scripts/install-cert.sh /etc/letsencrypt/renewal-hooks/deploy/`.

## Troubleshooting

When running `docker compose up` with `-d` switch, the standard process is detached from standard output. To follow the log, use logs command:
```sh
docker compose logs -n 100 -f
```
If the docker daemon is configured to push logs to Cloud Watch, you can find out logs on Cloud Watch log groups.

To analyze network traffic, if the test host has wiresharek, you may display web traffic using wireshark:
```sh
docker exec authorization-service tcpdump -pi eth0 -w - -s0 dst port 8000 or src port 8000| wireshark -k -i -
```

## Custom Implementation
If you have a custom implementation, fork this repo and implement the customization. Then reference the fork from the input variable of the Terraform template in Orthweb.
