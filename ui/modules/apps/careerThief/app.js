'use strict';

// ─────────────────────────────────────────────────────────────────────────────
// Career Thief – UI Controller
// Reçoit les événements de career_modules_thief (GELUA) via guihooks.trigger()
// et affiche le prompt, la barre QTE, le réticule et les feedbacks.
// ─────────────────────────────────────────────────────────────────────────────

angular.module('beamng.apps')

.directive('careerThief', [function () {
  return {
    templateUrl : '/ui/modules/apps/careerThief/app.html',
    replace     : true,
    restrict    : 'EA',
    controller  : 'CareerThiefCtrl',
  };
}])

.controller('CareerThiefCtrl', ['$scope', '$timeout', function ($scope, $timeout) {

  $scope.showPrompt      = false;
  $scope.qteActive       = false;
  $scope.feedbackVisible = false;
  $scope.onCooldown      = false;
  $scope.cooldownPct     = 100;

  $scope.reticleVisible = false;
  $scope.reticleState   = 'idle';   // 'idle' | 'hover' | 'stolen' | 'blocked'

  $scope.targetPartName  = '';
  $scope.targetValue     = 0;

  $scope.qtePartName = '';
  $scope.qtePos      = 0;
  $scope.qteTimePct  = 100;
  $scope.successZone = 0.18;

  $scope.feedbackClass = '';
  $scope.feedbackIcon  = '';
  $scope.feedbackMsg   = '';
  $scope.feedbackSub   = '';

  $scope.wanted = { active: false, timeStr: '0:00' };

  var feedbackTimer = null;
  var qteStartTime  = null;
  var qteDuration   = 4000;
  var cooldownMax   = 1;
  var cooldownStart = 0;

  function pad2(n) { return n < 10 ? '0' + n : '' + n; }

  function formatTime(secs) {
    var s = Math.max(0, Math.floor(secs));
    return Math.floor(s / 60) + ':' + pad2(s % 60);
  }

  function cancelFeedback() {
    if (feedbackTimer) {
      $timeout.cancel(feedbackTimer);
      feedbackTimer = null;
    }
  }

  function showFeedback(cls, icon, msg, sub, durationSec) {
    cancelFeedback();
    $scope.feedbackClass   = cls;
    $scope.feedbackIcon    = icon;
    $scope.feedbackMsg     = msg;
    $scope.feedbackSub     = sub || '';
    $scope.feedbackVisible = true;
    $scope.qteActive       = false;

    feedbackTimer = $timeout(function () {
      $scope.feedbackVisible = false;
    }, (durationSec || 3) * 1000);
  }

  // ── Gestionnaire central des événements GELUA ────────────────────────────────
  $scope.$on('careerThief_update', function (evt, d) {
    if (!d) return;

    switch (d.type) {

      case 'targetFound':
        $scope.showPrompt     = true;
        $scope.targetPartName = d.partName;
        $scope.targetValue    = d.value;
        $scope.onCooldown     = d.onCooldown;
        $scope.reticleVisible = true;
        $scope.reticleState   = d.alreadyStolen ? 'stolen' : (d.onCooldown ? 'blocked' : 'hover');
        if (d.onCooldown && d.cooldown > 0) {
          cooldownMax   = d.cooldown;
          cooldownStart = Date.now();
          $scope.cooldownPct = 100;
        }
        if (d.wanted) {
          $scope.wanted.active  = true;
          $scope.wanted.timeStr = formatTime(d.wantedTime);
        }
        break;

      case 'idle':
        $scope.showPrompt     = false;
        $scope.reticleVisible = true;
        $scope.reticleState   = 'idle';
        if (d.wanted) {
          $scope.wanted.active  = true;
          $scope.wanted.timeStr = formatTime(d.wantedTime);
        }
        break;

      case 'noTarget':
        $scope.showPrompt = false;
        showFeedback('ct-warn', 'x', 'Aucune pièce visée', 'Regardez une partie du véhicule', 1.5);
        break;

      case 'alreadyStolen':
        showFeedback('ct-warn', 'o', 'Déjà volée : ' + (d.partName || ''), 'Visez une autre zone', 2.0);
        break;

      case 'qteStart':
        cancelFeedback();
        $scope.showPrompt      = false;
        $scope.reticleVisible  = false;
        $scope.feedbackVisible = false;
        $scope.qteActive       = true;
        $scope.qtePartName     = d.partName;
        $scope.qtePos          = 0;
        $scope.qteTimePct      = 100;
        $scope.successZone     = d.successZone || 0.18;
        qteDuration            = (d.duration || 4) * 1000;
        qteStartTime           = Date.now();
        break;

      case 'qteTick':
        if ($scope.qteActive) {
          $scope.qtePos     = d.pos;
          var elapsed       = Date.now() - (qteStartTime || Date.now());
          $scope.qteTimePct = Math.max(0, 100 - (elapsed / qteDuration) * 100);
        }
        break;

      case 'qteSuccess':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(120);
        showFeedback('ct-success', '+', d.partName + ' volée !', 'Envoyée dans My Parts', 3.5);
        break;

      case 'qteFail':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(120);
        if (d.reason === 'inventory_failed') {
          showFeedback('ct-fail', '!', 'Transfert échoué', 'Inventaire BeamNG indisponible (voir F10)', 4);
        } else {
          showFeedback('ct-fail', 'x', 'Raté !', 'Police alertée', 3);
        }
        break;

      case 'qteTimeout':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(120);
        showFeedback('ct-fail', '#', 'Trop lent !', 'Police alertée', 3);
        break;

      case 'wantedStart':
        $scope.wanted.active  = true;
        $scope.wanted.timeStr = formatTime(d.duration);
        break;

      case 'wantedEnd':
        $scope.wanted.active = false;
        break;

      case 'onCooldown':
        showFeedback('ct-warn', '.', 'Attendez ' + Math.ceil(d.remaining) + ' s', '', 1.8);
        break;

      case 'inventoryUnavailable':
        // Cas critique : l'API BeamNG My Parts n'est pas accessible.
        var reason = d.reason === 'no_api'
          ? "API career_modules_partInventory absente"
          : "Aucune signature d'ajout n'a fonctionné";
        showFeedback('ct-fail', '!', 'Inventaire BeamNG indisponible', reason + ' — voir console F10', 5);
        break;

      case 'moduleReady':
        $scope.showPrompt      = false;
        $scope.qteActive       = false;
        $scope.feedbackVisible = false;
        $scope.wanted.active   = false;
        $scope.reticleVisible  = true;
        $scope.reticleState    = 'idle';
        if (d.apiHealthy === false) {
          showFeedback('ct-warn', '!', 'Attention', 'Inventaire BeamNG non détecté — voir F10', 6);
        }
        break;

      case 'hide':
        cancelFeedback();
        $scope.showPrompt      = false;
        $scope.qteActive       = false;
        $scope.feedbackVisible = false;
        $scope.wanted.active   = false;
        $scope.reticleVisible  = false;
        break;
    }
  });

  $scope.$on('$destroy', function () {
    cancelFeedback();
  });

}]);
