#!/usr/bin/env python

import math
import os.path
import sys
from collections import OrderedDict
import numpy as np
import osgeo
import shapely
from shapely.geometry import mapping, shape, box, Point, Polygon, LineString
from sklearn.cluster import KMeans
import fiona
#import matplotlib.pyplot as plt


def compactness(p):
    '''Computes the proportion of the area of the circumcircle 
    of the polygon and the area of the polygon'''
    dia = diameter(p)
    area_circle = math.pi * dia**2 / float(4)
    area_polygon = p.area
    comp = area_polygon/float(area_circle)
    return comp


def diameter(p):
    '''Computes maximal extend in x and y directions an returns the greater one'''
    [minx, miny, maxx, maxy] = p.bounds
    liney = LineString([(minx, miny), (maxx, miny)])
    linex = LineString([(minx, miny), (minx, maxy)])
    return max(liney.length,linex.length)


def diameter_small(p):
    '''Computes maximal extend in x and y directions an returns the smaller one'''
    [minx, miny, maxx, maxy] = p.bounds
    return min(maxx-minx, maxy-miny)

def properties(p):
    ''' Returns area, compactness and perimeter of a polygon'''
    a = p.area
    per = p.length
    d = diameter_small(p)
    return [a, per, d]


def classification_inside(file_o, file_n, file_outline):
    with fiona.open(file_outline, 'r') as outline:
        with fiona.open(file_o, 'r') as old:
            for out in outline:
                o = shape(out['geometry'])
                prop = np.array([[0, 0, 0]])
                rad = np.array([0])
                i = 0
                for polygon in old:
                    p = shape(polygon['geometry'])
                    if o.contains(p):
                        prop=np.append(prop, [properties(p)],0)
                        rad=np.append(rad, diameter_small(p))
                        i = i + 1
                    elif o.intersects(p):
                        intersect = o.intersection(p)
                        if not intersect.is_empty:
                            if mapping(intersect)['type'] == 'MultiPolygon':
                                for geom in intersect.geoms:
                                    prop=np.append(prop, [properties(geom)],0)
                                    rad=np.append(rad, diameter_small(geom))
                                    i = i + 1
                            else:
                                prop=np.append(prop, [properties(intersect)],0)
                                rad=np.append(rad, diameter_small(intersect))
                                i = i + 1
    prop = np.delete(prop,0,0)
    rad = np.delete(rad,0,0)
    prop = np.divide(prop, np.absolute(prop).max(0))
    n_clusters = 100
    n_polygons = prop.shape[0]
    if n_clusters > n_polygons:
        n_clusters = n_polygons/2
    k = KMeans(n_clusters=n_clusters)
    k.fit(prop)
    krig = k.predict(prop)
    #plt.figure(1)
    #plt.scatter(rad, krig, c=krig)
    #plt.show()
    for j in xrange(n_clusters):
        if not rad[krig == j] == []:
            rad[krig == j] = np.max(rad[krig == j])
        else:
            print "cluster number", j, "doesn't exist"
    i = 0
    with fiona.open(file_o, 'r') as old:
        schema = old.schema
        schema['properties'].update({u'krig': 'int'})
        del schema['properties']['DN']
        with fiona.open(file_n, 'w', 'ESRI Shapefile', schema, old.crs)\
                as new:
            with fiona.open(file_outline, 'r') as outline:
                for out in outline:
                    o = shape(out['geometry'])
                    for polygon in old:
                        p = shape(polygon['geometry'])
                        if o.contains(p):
                            polygon['properties']\
                                .update({u'krig': int(rad[i])})
                            del polygon['properties']['DN']
                            new.write({'properties': polygon['properties'], 'geometry': polygon['geometry']})
                            i = i + 1
                        elif o.intersects(p):
                            intersect = o.intersection(p)
                            if not intersect.is_empty:
                                if mapping(intersect)['type'] == \
                                   'MultiPolygon':
                                    for geom in intersect.geoms:
                                        geom = mapping(geom)
                                        new.write({'properties': {u'krig': int(rad[i])},
                                                   'geometry':geom})
                                        i = i + 1
                                else:
                                    intersect = mapping(intersect)
                                    new.write({'properties': {u'krig': int(rad[i])},
                                               'geometry': intersect})
                                    i = i + 1


def classification(file_o, file_n):
    with fiona.open(file_o, 'r') as old:
        n_polygons = len(list(old))
        prop = np.empty([n_polygons, 3])
        rad = np.empty([n_polygons, 1])
        i = 0
        for polygon in old:
            p = shape(polygon['geometry'])
            prop[i] = properties(p)
            rad[i] = diameter(p)+500
            i = i + 1
    prop = np.divide(prop, np.absolute(prop).max(0))
    n_clusters = 150
    if n_clusters > n_polygons:
        n_clusters = n_polygons
    k = KMeans(n_clusters=n_clusters)
    k.fit(prop)
    krig = k.predict(prop)
    for j in xrange(n_clusters):
        rad[krig == j] = np.max(rad[krig == j])
    i = 0
    with fiona.open(file_o, 'r') as old:
        schema = old.schema
        schema['properties'].update({u'krig': 'int'})
        with fiona.open(file_n, 'w', 'ESRI Shapefile', schema, old.crs)\
                as new:
            for polygon in old:
                polygon['properties'].update({u'krig': int(rad[i])})
                i = i + 1
                new.write({'properties': polygon['properties'],
                           'geometry': polygon['geometry']})


if __name__ == "__main__":
    file_old = sys.argv[1]
    file_new = sys.argv[2]
    file_out = sys.argv[3]
    if os.path.exists(file_out):
        print "outline exists"
        classification_inside(file_old, file_new, file_out)
    else:
        classification(file_old, file_new)
        print "outline does not exist"
