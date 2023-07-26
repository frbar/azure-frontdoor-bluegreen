targetScope = 'resourceGroup'

@description('The name of the environment. This will also suffix all resources. Lowercase and no space.')
param envName string

@description('Location for all resources.')
param location string = resourceGroup().location

param frontDoorSkuName string = 'Standard_AzureFrontDoor'

// front door

resource frontDoorProfile 'Microsoft.Cdn/profiles@2021-06-01' = {
  name: '${envName}-afd'
  location: 'global'
  sku: {
    name: frontDoorSkuName
  }
}

resource frontDoorEndpoint 'Microsoft.Cdn/profiles/afdEndpoints@2021-06-01' = {
  name: '${envName}-afd'
  parent: frontDoorProfile
  location: 'global'
  properties: {
    enabledState: 'Enabled'
  }
}

// Front Door - API

resource frontDoorOriginGroupApi 'Microsoft.Cdn/profiles/originGroups@2021-06-01' = [for i in range(0, 2): {
  name: 'api-origin-group-${i}'
  parent: frontDoorProfile
  properties: {
    loadBalancingSettings: {
      sampleSize: 4
      successfulSamplesRequired: 3
    }
    healthProbeSettings: {
      probePath: '/health'
      probeRequestType: 'GET'
      probeProtocol: 'Http'
      probeIntervalInSeconds: 10
    }
  }
}]

resource frontDoorOriginApi 'Microsoft.Cdn/profiles/originGroups/origins@2021-06-01' = [for i in range(0, 2): {
  name: 'api-origin-${i}'
  parent: frontDoorOriginGroupApi[i]
  properties: {
    hostName: appService[i].properties.defaultHostName
    httpPort: 80
    httpsPort: 443
    originHostHeader: appService[i].properties.defaultHostName
    priority: (i + 1)
    weight: 1000
    enforceCertificateNameCheck: false
  }
}]

resource frontDoorRouteApi 'Microsoft.Cdn/profiles/afdEndpoints/routes@2021-06-01' = {
  name: 'api-route'
  parent: frontDoorEndpoint
  dependsOn: [
    frontDoorOriginApi // This explicit dependency is required to ensure that the origin group is not empty when the route is created.
  ]
  properties: {
    originGroup: {
      id: frontDoorOriginGroupApi[0].id // by default, route to 0 - we'll use a rule to override this
    }
    supportedProtocols: [
      'Http'
      'Https'
    ]
    patternsToMatch: [
      '/api/*'
    ]
    forwardingProtocol: 'HttpsOnly'
    linkToDefaultDomain: 'Enabled'
    httpsRedirect: 'Enabled'
    ruleSets: [
      {
        id: frontDoorRuleSet.id
      }
    ]
  }
}

resource frontDoorRuleSet 'Microsoft.Cdn/profiles/rulesets@2022-11-01-preview' = {
  parent: frontDoorProfile
  name: 'ruleset1'
}

resource frontDoorRuleGreen 'Microsoft.Cdn/profiles/rulesets/rules@2022-11-01-preview' = {
  parent: frontDoorRuleSet
  name: 'routetogreen'
  properties: {
    actions: [
      {
        name: 'RouteConfigurationOverride'
        parameters: {
          originGroupOverride: {
            forwardingProtocol: 'MatchRequest'
            originGroup: {
              id: frontDoorOriginGroupApi[1].id
            }
          }
          typeName: 'DeliveryRuleRouteConfigurationOverrideActionParameters'
        }
      }
    ]
    conditions: [
      {
        name: 'RequestHeader'
        parameters: {
          matchValues: [
            'green'
          ]
          negateCondition: false
          operator: 'Equal'
          selector: 'X-Color'
          transforms: []
          typeName: 'DeliveryRuleRequestHeaderConditionParameters'
        }
      }
    ]
    matchProcessingBehavior: 'Continue'
    order: 0
  }
  dependsOn: [
    frontDoorOriginApi // This explicit dependency is required to ensure that the origin group is not empty when the route is created.
  ]
}

// 2 API backends

resource appServicePlan 'Microsoft.Web/serverfarms@2020-06-01' = [for i in range(0, 2): {
  name: '${envName}-plan-${i}'
  location: location
  properties: {
    reserved: true
  }
  sku: {
    name: 'B1'
  }
  kind: 'linux'
}]

resource appService 'Microsoft.Web/sites@2020-06-01' = [for i in range(0, 2): {
  name: '${envName}-api-${i}'
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  properties: {
    serverFarmId: appServicePlan[i].id
    clientAffinityEnabled: false
    siteConfig: {
      linuxFxVersion: 'DOTNETCORE|6.0'
      appSettings: [
        {
          name: 'WEBSITE_RUN_FROM_PACKAGE'
          value: '1'
        }
        {
          name: 'Environment'
          value: '${i}'
        }
      ]
      healthCheckPath: '/health'
      ipSecurityRestrictions: [
        {
          tag: 'ServiceTag'
          ipAddress: 'AzureFrontDoor.Backend'
          action: 'Allow'
          priority: 100
          headers: {
            'x-azure-fdid': [
              frontDoorProfile.properties.frontDoorId
            ]
          }
          name: 'Allow traffic from Front Door'
        }
      ]
    }
  }
}]

// Outputs
output frontDoorId string = frontDoorProfile.id
output frontDoorEndpoint string = frontDoorEndpoint.properties.hostName
