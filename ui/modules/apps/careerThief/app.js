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

  $scope.modeLabel = 'BlackMarket';
  $scope.statusLabel = 'En attente';
  $scope.vehicleName = '-';
  $scope.dropoffName = 'Docks';
  $scope.distance = 0;
  $scope.integrity = 1;
  $scope.speed = 0;
  $scope.cooldown = 0;

  $scope.feedbackVisible = false;
  $scope.feedbackClass = 'ct-warn';
  $scope.feedbackIcon = '!';
  $scope.feedbackMsg = '';
  $scope.feedbackSub = '';

  $scope.wanted = { active: false, timeStr: '0:00' };

  $scope.market = {
    hasListing: false,
    vehicleName: '',
    askingPrice: 0,
    integrity: 0,
    offerIn: 0
  };

  $scope.offer = {
    active: false,
    buyer: '',
    amount: 0,
    askingPrice: 0
  };

  var feedbackTimer = null;

  function pad2(n) {
    return n < 10 ? '0' + n : '' + n;
  }

  function formatTime(secs) {
    var s = Math.max(0, Math.floor(secs || 0));
    return Math.floor(s / 60) + ':' + pad2(s % 60);
  }

  function clearFeedbackTimer() {
    if (feedbackTimer) {
      $timeout.cancel(feedbackTimer);
      feedbackTimer = null;
    }
  }

  function showFeedback(level, msg, sub, durationSec) {
    clearFeedbackTimer();
    $scope.feedbackClass = level === 'success' ? 'ct-success' : (level === 'fail' ? 'ct-fail' : 'ct-warn');
    $scope.feedbackIcon = level === 'success' ? '+' : (level === 'fail' ? 'x' : '!');
    $scope.feedbackMsg = msg || '';
    $scope.feedbackSub = sub || '';
    $scope.feedbackVisible = true;
    feedbackTimer = $timeout(function () {
      $scope.feedbackVisible = false;
    }, (durationSec || 2.8) * 1000);
  }

  function callLua(fnName) {
    if (window.bngApi && typeof window.bngApi.engineLua === 'function') {
      window.bngApi.engineLua("if career_modules_thief then career_modules_thief." + fnName + "() end");
    }
  }

  $scope.acceptOffer = function () { callLua('acceptBestOffer'); };
  $scope.rejectOffer = function () { callLua('rejectOffer'); };
  $scope.cancelListing = function () { callLua('cancelListing'); };

  $scope.$on('careerThief_update', function (evt, d) {
    if (!d) return;

    switch (d.type) {
      case 'moduleReady':
        $scope.statusLabel = 'Pret pour le vol';
        $scope.feedbackVisible = false;
        $scope.offer.active = false;
        $scope.market.hasListing = false;
        break;

      case 'idle':
        $scope.statusLabel = 'Cherche une voiture cible';
        $scope.cooldown = d.cooldown || 0;
        if (d.wanted) {
          $scope.wanted.active = true;
          $scope.wanted.timeStr = formatTime(d.wantedTime);
        }
        break;

      case 'theftStarted':
        $scope.vehicleName = d.vehicleName || '-';
        $scope.dropoffName = d.dropoffName || 'Docks';
        $scope.statusLabel = 'Livraison vers ' + $scope.dropoffName;
        showFeedback('success', 'Voiture volee', 'Direction: ' + $scope.dropoffName, 2.5);
        break;

      case 'missionUpdate':
        $scope.statusLabel = d.status || 'mission';
        $scope.vehicleName = d.vehicleName || '-';
        $scope.dropoffName = d.dropoffName || 'Docks';
        $scope.distance = d.distanceToDropoff || 0;
        $scope.integrity = d.integrity || 0;
        $scope.speed = d.speed || 0;
        if (d.wanted) {
          $scope.wanted.active = true;
          $scope.wanted.timeStr = formatTime(d.wantedTime);
        }
        break;

      case 'listingCreated':
        $scope.market.hasListing = true;
        $scope.market.vehicleName = d.vehicleName || '';
        $scope.market.askingPrice = d.askingPrice || 0;
        $scope.market.integrity = d.integrity || 0;
        $scope.statusLabel = 'Annonce BlackMarket creee';
        showFeedback('success', 'Annonce en ligne', 'Prix demande: ' + (d.askingPrice || 0), 3.2);
        break;

      case 'marketState':
        $scope.market.hasListing = !!d.hasListing;
        if (d.hasListing) {
          $scope.market.vehicleName = d.vehicleName || '';
          $scope.market.askingPrice = d.askingPrice || 0;
          $scope.market.integrity = d.integrity || 0;
          $scope.market.offerIn = d.offerIn || 0;
        } else {
          $scope.market.offerIn = 0;
        }
        break;

      case 'offerUpdate':
        $scope.offer.active = true;
        $scope.offer.buyer = d.buyer || 'Client';
        $scope.offer.amount = d.amount || 0;
        $scope.offer.askingPrice = d.askingPrice || 0;
        showFeedback('warn', 'Nouvelle offre', (d.buyer || 'Client') + ' propose ' + (d.amount || 0), 3.5);
        break;

      case 'saleComplete':
        $scope.offer.active = false;
        $scope.market.hasListing = false;
        $scope.statusLabel = 'Vente terminee';
        showFeedback('success', 'Vente conclue', (d.buyer || 'Client') + ' a paye ' + (d.amount || 0), 3.8);
        break;

      case 'feedback':
        showFeedback(d.level || 'warn', d.message || '', d.sub || '', 2.8);
        break;

      case 'wantedStart':
        $scope.wanted.active = true;
        $scope.wanted.timeStr = formatTime(d.duration);
        break;

      case 'wantedEnd':
        $scope.wanted.active = false;
        break;

      case 'hide':
        clearFeedbackTimer();
        $scope.feedbackVisible = false;
        $scope.wanted.active = false;
        $scope.offer.active = false;
        $scope.market.hasListing = false;
        break;
    }
  });

  $scope.$on('$destroy', function () {
    clearFeedbackTimer();
  });
}]);
