<?php
namespace app\config;

use nur\v\bs3\Bs3IconManager;

class cdefaults {
  const APP = [
    "debug" => false,

    "menu" => [
      "items" => [
        [[Bs3IconManager::REFRESH, "&nbsp;Rafraichir"], "",
          "accesskey" => "a",
        ],
      ],
    ],
  ];
}
