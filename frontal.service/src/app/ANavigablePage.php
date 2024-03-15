<?php
namespace app\app;

use Exception;
use nur\A;
use nur\F;
use nur\path;
use nur\txt;
use nur\v\bs3\vc\CNavTabs;
use nur\v\http;
use nur\v\page;
use nur\v\vp\NavigablePage;

class ANavigablePage extends NavigablePage {
  const CSS = ["frontal.css"];
  const NAVBAR_OPTIONS = [
    "brand" => [
      "<img src='brand.png' width='50' height='50' alt='Logo'/>",
      "<span style='margin-right: 1em;'>&nbsp;<b>RDDTOOLS</b></span>",
    ],
    "show_brand" => "asis",
  ];
  const REQUIRE_AUTH = false;
  const REQUIRE_AUTHZ = false;
  const REQUIRE_PERM = "connect";

  protected $haveContent = true;
  function haveContent(): bool {
    return $this->haveContent;
  }

  function download(string $dldir, array $files): bool {
    $dl = F::get("dl");
    if (!$dl) return false;
    # télécharger un fichier
    $dl = path::filename($dl);
    if (in_array($dl, $files)) {
      header("x-sendfile: $dldir/$dl");
      http::content_type();
      http::download_as($dl);
      $this->haveContent = false;
    } else {
      throw new Exception("$dl: fichier invalide");
    }
    return true;
  }
}
