#!/usr/bin/env python3
"""
SYNOPSIS
mft_derby_size_checker.py:

__DESCRIPTION__
        Monitors the MFT derby disk space sending email notifications.
__AUTHOR__
       Glory Mae Llego <glorymae.llego@onsemi.com>

__LICENSE__
       (C) onsemi 2023 All rights reserved.
"""


import argparse
import yaml
import paramiko
import smtplib
from email.mime.text import MIMEText
import sys
from email.mime.multipart import MIMEMultipart
import re

# Define du_command
du_command = "du -h ewbmft/Geronimo-2.2/var/derby/edb*/seg0"
smtp_server = "mailhost.onsemi.com"

#Define config file path
def parse_yaml(file_path):
    with open(file_path, 'r') as file:
        try:
            data = yaml.safe_load(file)
            return data
        except yaml.YAMLError as e:
            print(f"Error parsing YAML: {e}")

#Define SSH server connect
def ssh_to_host(hostname, username, password, command):
    ssh = paramiko.SSHClient()
    ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    result_dict = {}
    try:
        ssh.connect(hostname, username=username, password=password)
        stdin, stdout, stderr = ssh.exec_command(command)
        # Read the output line by line and store it in a dictionary
        for line in stdout:
            parts = line.strip().split()
            if len(parts) == 2:
                path_parts = parts[1].split('/')
                for i, part in enumerate(path_parts):
                    dict_name = f'{hostname}_{part}'
                    if hostname == 'ewb-dl-ap2':
                      if part == 'edbcp' or part == 'edbsz':
                        result_dict[part] = parts[0]
                    if hostname == 'ewb-dl-ap3':
                      if part == 'edbbk':
                        result_dict[part] = parts[0]
                    if hostname == 'ewb-dl-us':
                      if part == 'edbfound' or part == 'edbme' or part == 'edbsl':
                        result_dict[part] = parts[0]

    except paramiko.AuthenticationException:
        print("Authentication failed, please verify your credentials.")
    except paramiko.SSHException as e:
        print(f"SSH connection failed: {e}")
    finally:
        ssh.close()
    return result_dict

#Define send email
def send_mail(sender, recipient, body, subject):
    # Set sender, receiver, and cc emails
    sender_email = sender
    receiver_emails = [recipient]
    body_content = body
    subject_content = subject

    # Create MINE message
    mail_msg = MIMEMultipart('alternative')
    mail_msg['Subject'] = subject_content 
    mail_msg['From'] = sender_email
    mail_msg['To'] = recipient

    part1 = MIMEText(body_content, 'html')
    mail_msg.attach(part1)

    # Send email  
    with smtplib.SMTP(smtp_server) as server:
        server.sendmail(sender_email, receiver_emails, mail_msg.as_string())

#Parse command line arguments to get server credentials file path
parser = argparse.ArgumentParser()
parser.add_argument("--server_credentials", required=True, help='MFT server credentials file path')
args = parser.parse_args()
parsed_data = parse_yaml(args.server_credentials)
# Iterate over each host in parsed YAML data:
# Execute du_command on the host using SSH
msg = ""
disk_usage_alerts = {}
for host in parsed_data.get('hosts', []):
    disk_usage = ssh_to_host(host['name'], host['username'], host['password'], du_command)
    for db in disk_usage:
      dic_name = f"{host['name']}_{db}"
      disk_usage_alerts[dic_name] = { "site": db,"size": disk_usage[db]}
# Email Recipient
recipient = "yms.admins@onsemi.com"
sender = "yms.admins@onsemi.com"
subject = "MFT Derby Database Size Report"

# HTML content for email notification:
html = """
<html>
<head>
<style>

body {
  font-family: Arial, sans-serif;
  border: 1px solid #ddd;
}


.report {
  border: 1px solid #2299ee; 
  padding: 20px;
  max-width: 800px;
  margin: 0 auto;
}

h1 {
  text-align: center; 
  color: #808080;
}

table {
  width: 100%;
  border-collapse: collapse; 
}

th {
  background-color: #FFA500;
  color: white;
  padding: 10px; 
  text-align: left;
}

td { 
  border: 1px solid #eee;
  padding: 10px;
}

.size {
  font-weight: bold;
}

#.red {
#  color: red;
#}
.size_red {
  color: white;
  font-weight: bold !important;
  background-color: #FF0000;
}

</style>

</head>

<body>

<div class="report">

<h1>MFT Derby Database Size</h1> 

<table>
  <tr>
    <th>Host</th>  
    <th>Site</th>
    <th>Size</th>
  </tr>
"""
pattern = r'\d+(\.\d+)?'
for host, details in disk_usage_alerts.items():
    final_host = host.split('_')
    derby_size = re.search(pattern, details['size']).group()
    unit = details['size'][-1]
    print(unit)
    if unit == 'K':
        derby_size = float(derby_size) / 1000000
    if unit == 'M':
        derby_size = float(derby_size) / 1024
    size_class = "size" if float(derby_size) < 5.0 else "size_red"
    print(size_class)
    html += f"""
  <tr>
    <td>{final_host[0]}</td>
    <td>{details['site']}</td> 
    <td class="{size_class}">{details['size']}</td>
  </tr>
"""

html += """
</table>

</div>

</body>
</html>
"""
# Send email notification with the HTML content and print alerts
if disk_usage_alerts:
    print(f"Alerts: {disk_usage_alerts}")
    send_mail(sender, recipient, html, subject)

# END
