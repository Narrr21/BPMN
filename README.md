Jalanin:
npm i
.\setup.ps1

Ganti bpmn (order-payment.bpmn) di folder BPMN dengan file bpmn yang baru.
tambahkan dengan menjalankan
.\setup.ps1

Ganti juga bagian ini pada setup.ps1:
[string]$ProcessFile = (Join-Path $PSScriptRoot "order-payment.bpmn"), <== Ganti dengan nama file bpmn yang baru
