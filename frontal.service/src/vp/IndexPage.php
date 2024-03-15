<?php
namespace app\vp;

use app\app\ANavigablePage;
use nulib\cl;
use nur\A;
use nur\F;
use nur\file;
use nur\io\line\LineReader;
use nur\path;
use nur\shutils;
use nur\SV;
use nur\txt;
use nur\v\bs3\vc\CListGroup;
use nur\v\bs3\vc\CNavTabs;
use nur\v\bs3\vc\CVerticalTable;
use nur\v\page;
use nur\v\v;
use nur\v\vo;

class IndexPage extends ANavigablePage {
  const TITLE = "RDDTOOLS";

  function loadVersions(string $wksdir): array {
    $envfile = "$wksdir/.env";
    $rddtools = "?";
    $mypegase = "?";
    $pivotbdd = "?";
    if (file_exists($envfile)) {
      $reader = new LineReader($envfile);
      foreach ($reader as $line) {
        if (preg_match("/^RDDTOOLS_VERSION=(.*)/", $line, $ms)) {
          $rddtools = $ms[1];
        } elseif (preg_match("/^MYPEGASE_VERSION=(.*)/", $line, $ms)) {
          $mypegase = $ms[1];
        } elseif (preg_match("/^PIVOTBDD_VERSION=(.*)/", $line, $ms)) {
          $pivotbdd = $ms[1];
        }
      }
    }
    return [
      "rddtools" => $rddtools,
      "mypegase" => $mypegase,
      "pivotbdd" => $pivotbdd,
    ];
  }

  function setup(): void {
    $releaseCourante = null;
    $devimageCourante = null;
    $basedir = "/var/www/app";
    if (is_link("$basedir/release-courante.wks")) {
      $releaseCourante = readlink("$basedir/release-courante.wks");
    }
    if (is_link("$basedir/devimage-courante.wks")) {
      $devimageCourante = readlink("$basedir/devimage-courante.wks");
    }
    $wksdirs = shutils::ls_dirs($basedir, "*.wks");
    $workshops = [];
    foreach ($wksdirs as $wksdir) {
      if (file_exists("$basedir/$wksdir/.uninitialized_wks")) continue;
      $versions = $this->loadVersions("$basedir/$wksdir");
      $workshops[] = [
        "name" => $wksdir,
        "path" => "$basedir/$wksdir",
        "release" => $wksdir === $releaseCourante,
        "devimage" => $wksdir === $devimageCourante,
        "rddtools_version" => $versions["rddtools"],
        "mypegase_version" => $versions["mypegase"],
        "pivotbdd_version" => $versions["pivotbdd"],
      ];
    }
    $this->workshops = cl::usorted($workshops, ["-devimage", "-release", "name"]);
  }

  protected $workshops;

  function print(): void {
    vo::h2("Accès aux bases pivot");
    new CListGroup([
      "pgAdmin" => ["/pgadmin/", "Un outil simple et ergonomique"],
      //"Adminer" => ["/adminer/", "Une alternative préférée par certains informaticiens"],
    ], [
      "container" => "div",
      "map_func" => function ($item, $title) {
        [$url, $desc] = $item;
        return [
          "href" => $url,
          $title,
          " -- ",
          $desc,
        ];
      },
      "autoprint" => true,
    ]);
    vo::h2("Ateliers");
    new CListGroup($this->workshops, [
      "map_func" => function ($wks) {
        return [
          $wks["name"],
          v::span([
            "class" => "text-muted",
            $wks["devimage"]? " -- devimage courante": null,
            $wks["release"]? " -- release courante": null,
            ", rddtools ", $wks["rddtools_version"],
            ", mypegase ", $wks["mypegase_version"],
            ", pivotbdd ", $wks["pivotbdd_version"],
          ]),
        ];
      },
      "autoprint" => true,
    ]);
  }
}
